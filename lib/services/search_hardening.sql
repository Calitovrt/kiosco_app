-- =====================================================
-- HARDENING DEL BUSCADOR DE ALUMNOS - kiosco_app
-- Archivo #15 de SQL_APPLY_ORDER.md
--
-- Correr DESPUES de chat_messages.sql
-- =====================================================
--
-- EL PROBLEMA
--
-- search_student_names(p_query) es SECURITY DEFINER, la puede llamar
-- anon, y hace `name ILIKE '%' || p_query || '%'`. Con p_query = ''
-- el patron queda '%%' y devuelve los primeros 10 alumnos del padron.
-- Variando la letra, cualquiera saca el colegio entero de a 10.
--
-- El anon key esta publicado en el repo (lib/core/env.dart): es
-- publico por diseno, no es un secreto. Por eso RLS protege la tabla
-- `students` pero esta funcion la saltea a proposito, para el
-- autocompletado del login.
--
-- Verificado 2026-11-24: POST /rpc/search_student_names con
-- p_query "" devolvia 10 filas sin ninguna credencial.
--
-- LA MITIGACION
--
-- 1. Minimo 3 caracteres. Sin eso no hay autocompletado util igual:
--    nadie busca su nombre con una letra sola.
-- 2. Rate limit por IP: 40 busquedas por minuto. Enumerar el padron
--    pasa de segundos a horas.
--
-- Esto NO cierra la enumeracion del todo: sigue siendo un buscador
-- por nombre. El cierre real es dejar de buscar por nombre en el
-- login (usar el codigo de activacion). Queda como pendiente.
-- =====================================================

-- =====================================================
-- 1. TABLA DE CONTROL (mismo patron que login_guard)
-- Sin policies + RLS: solo la tocan las funciones SECURITY DEFINER.
-- =====================================================

CREATE TABLE IF NOT EXISTS public.search_guard (
  ip                TEXT PRIMARY KEY,
  hits              INT NOT NULL DEFAULT 0,
  window_started_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.search_guard ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.search_guard FROM PUBLIC, anon, authenticated;

-- =====================================================
-- 2. HELPERS INTERNOS
-- =====================================================

CREATE OR REPLACE FUNCTION public._search_client_ip()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = 'public'
AS $$
  -- PostgREST pone x-forwarded-for. Fuera de PostgREST (SQL Editor)
  -- no hay header: todo cae en 'desconocido'.
  SELECT COALESCE(
    NULLIF(split_part(
      COALESCE(current_setting('request.headers', true)::json->>'x-forwarded-for', ''),
      ',', 1), ''),
    'desconocido');
$$;

CREATE OR REPLACE FUNCTION public._search_rate_ok(
  p_ip TEXT,
  p_max INT DEFAULT 40,
  p_window INTERVAL DEFAULT '1 minute'
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_hits INT;
BEGIN
  INSERT INTO public.search_guard (ip, hits, window_started_at)
  VALUES (p_ip, 1, now())
  ON CONFLICT (ip) DO UPDATE SET
    hits = CASE
             WHEN public.search_guard.window_started_at < now() - p_window THEN 1
             ELSE public.search_guard.hits + 1
           END,
    window_started_at = CASE
                          WHEN public.search_guard.window_started_at < now() - p_window THEN now()
                          ELSE public.search_guard.window_started_at
                        END
  RETURNING hits INTO v_hits;

  RETURN v_hits <= p_max;
END;
$$;

-- =====================================================
-- 3. EL BUSCADOR, CON MINIMO Y RATE LIMIT
-- Deja de ser LANGUAGE sql porque ahora tiene logica y early return.
-- =====================================================

CREATE OR REPLACE FUNCTION public.search_student_names(p_query TEXT)
RETURNS TABLE(id UUID, name TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_q TEXT := btrim(COALESCE(p_query, ''));
  v_pattern TEXT;
BEGIN
  -- Query vacia o de 1-2 letras: no devuelve nada en vez de devolver
  -- el padron. `RETURN` en una funcion RETURNS TABLE = conjunto vacio.
  IF length(v_q) < 3 THEN
    RETURN;
  END IF;

  -- Neutralizar los comodines de LIKE. Sin esto, '%%%' pasaba el minimo de
  -- 3 caracteres y devolvia el padron igual: el largo se medía sobre el
  -- texto crudo, pero el patron resultante matcheaba todo.
  v_q := replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_');
  v_pattern := '%' || v_q || '%';

  IF NOT public._search_rate_ok(public._search_client_ip()) THEN
    RETURN;
  END IF;

  RETURN QUERY
    SELECT s.id, s.name
    FROM public.students s
    WHERE s.deleted IS NOT TRUE
      AND s.name ILIKE v_pattern ESCAPE '\'
    ORDER BY s.name
    LIMIT 10;
END;
$$;

-- =====================================================
-- 4. GRANTS
-- =====================================================

REVOKE ALL ON FUNCTION public.search_student_names(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.search_student_names(TEXT) TO anon, authenticated;

-- Los helpers solo los usan las funciones SECURITY DEFINER (corren
-- como owner), nunca el cliente.
REVOKE ALL ON FUNCTION public._search_client_ip() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._search_rate_ok(TEXT, INT, INTERVAL) FROM PUBLIC, anon, authenticated;

-- =====================================================
-- VERIFICACION
-- =====================================================
--
-- a) Query vacia -> 0 filas (antes devolvia 10):
--
--   SELECT count(*) FROM public.search_student_names('');
--   SELECT count(*) FROM public.search_student_names('ab');
--
-- b) Query de 3+ letras -> devuelve resultados:
--
--   SELECT count(*) FROM public.search_student_names('ana');
--
-- c) Rate limit: correr 45 veces la misma query en menos de un minuto
--    y las ultimas tienen que devolver 0 filas.
--
--   SELECT count(*) FROM (
--     SELECT public.search_student_names('ana') FROM generate_series(1, 45)
--   ) t;
--
-- d) Desde afuera, con el anon key del repo (esto es lo que importa):
--
--   curl -s -X POST "https://<project>.supabase.co/rest/v1/rpc/search_student_names" \
--     -H "apikey: <anon>" -H "Authorization: Bearer <anon>" \
--     -H "Content-Type: application/json" -d '{"p_query":""}'
--   -- Esperado: []
