-- =====================================================
-- CHAT ALUMNO <-> KIOSCO - kiosco_app
-- Archivo #14 de SQL_APPLY_ORDER.md
--
-- Correr DESPUES de sale_checkout_atomic.sql.
--
-- Reemplaza conceptualmente al flujo de "enviar captura": ahora el
-- alumno (o su familia) escribe en un chat y adjunta el comprobante
-- ahi mismo. La tabla payment_captures queda como historial, sin uso
-- nuevo.
-- =====================================================
--
-- MODELO
--
-- No hay conversaciones ni hilos: el alumno ES el hilo. Todos sus
-- mensajes viven en una sola secuencia.
--
-- `read_at` se interpreta segun quien lo escribio:
--   sender = 'alumno'  -> read_at lo setea el KIOSCO al abrir el chat
--   sender = 'kiosco'  -> read_at lo setea el ALUMNO al abrir el chat
-- =====================================================

CREATE TABLE IF NOT EXISTS public.messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  sender TEXT NOT NULL CHECK (sender IN ('alumno', 'kiosco')),
  body TEXT,
  image_path TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  read_at TIMESTAMPTZ,
  -- Un mensaje sin texto y sin imagen no aporta nada.
  CONSTRAINT messages_has_content CHECK (
    (body IS NOT NULL AND btrim(body) <> '') OR image_path IS NOT NULL
  )
);

CREATE INDEX IF NOT EXISTS messages_student_idx
  ON public.messages (student_id, created_at DESC);

CREATE INDEX IF NOT EXISTS messages_unread_idx
  ON public.messages (sender, read_at)
  WHERE read_at IS NULL;

-- =====================================================
-- ACCESO DEL KIOSCO: admin autenticado, via RLS
-- El alumno NO toca la tabla: solo puede entrar por los RPC con token.
-- =====================================================

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS messages_admin_all ON public.messages;
CREATE POLICY messages_admin_all ON public.messages
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

REVOKE ALL ON TABLE public.messages FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE ON TABLE public.messages TO authenticated;

-- =====================================================
-- RPC DEL ALUMNO
-- =====================================================

-- 1. Enviar mensaje (texto, imagen o ambas cosas).
CREATE OR REPLACE FUNCTION public.send_student_message(
  p_student_id UUID,
  p_token TEXT,
  p_body TEXT,
  p_image_path TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF NOT public._student_token_ok(p_student_id, p_token) THEN
    RAISE EXCEPTION 'Token invalido';
  END IF;

  IF (p_body IS NULL OR btrim(p_body) = '')
     AND (p_image_path IS NULL OR p_image_path = '') THEN
    RAISE EXCEPTION 'Mensaje vacio';
  END IF;

  -- La imagen tiene que estar en la carpeta del alumno que la manda.
  IF p_image_path IS NOT NULL AND p_image_path <> ''
     AND split_part(p_image_path, '/', 1) IS DISTINCT FROM p_student_id::text THEN
    RAISE EXCEPTION 'Ruta de imagen invalida';
  END IF;

  INSERT INTO public.messages (student_id, sender, body, image_path)
  VALUES (
    p_student_id,
    'alumno',
    NULLIF(btrim(COALESCE(p_body, '')), ''),
    NULLIF(p_image_path, '')
  )
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('status', 'ok', 'id', v_id);
END;
$$;

-- 2. Leer el hilo propio (ultimos N, devueltos en orden cronologico).
CREATE OR REPLACE FUNCTION public.get_student_messages(
  p_student_id UUID,
  p_token TEXT,
  p_limit INT DEFAULT 200
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_result JSONB;
BEGIN
  IF NOT public._student_token_ok(p_student_id, p_token) THEN
    RAISE EXCEPTION 'Token invalido';
  END IF;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', m.id,
      'sender', m.sender,
      'body', m.body,
      'image_path', m.image_path,
      'created_at', m.created_at,
      'read_at', m.read_at
    ) ORDER BY m.created_at
  ), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT * FROM public.messages
    WHERE student_id = p_student_id
    ORDER BY created_at DESC
    LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 200), 500))
  ) m;

  RETURN v_result;
END;
$$;

-- 3. Marcar como leidos los mensajes del kiosco.
CREATE OR REPLACE FUNCTION public.mark_student_messages_read(
  p_student_id UUID,
  p_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_count INT;
BEGIN
  IF NOT public._student_token_ok(p_student_id, p_token) THEN
    RAISE EXCEPTION 'Token invalido';
  END IF;

  UPDATE public.messages
  SET read_at = now()
  WHERE student_id = p_student_id
    AND sender = 'kiosco'
    AND read_at IS NULL;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN jsonb_build_object('status', 'ok', 'marked', v_count);
END;
$$;

-- =====================================================
-- GRANTS: el alumno entra como anon, sin rol de base
-- =====================================================

REVOKE ALL ON FUNCTION public.send_student_message(UUID, TEXT, TEXT, TEXT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_student_message(UUID, TEXT, TEXT, TEXT)
  TO anon, authenticated;

REVOKE ALL ON FUNCTION public.get_student_messages(UUID, TEXT, INT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_student_messages(UUID, TEXT, INT)
  TO anon, authenticated;

REVOKE ALL ON FUNCTION public.mark_student_messages_read(UUID, TEXT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_student_messages_read(UUID, TEXT)
  TO anon, authenticated;

-- El validador de token es un oraculo: solo lo usan las funciones
-- SECURITY DEFINER (que corren como owner), nunca el cliente.
REVOKE ALL ON FUNCTION public._student_token_ok(UUID, TEXT) FROM PUBLIC, anon;

-- =====================================================
-- VERIFICACION
-- =====================================================
--
-- a) Tabla y privilegios:
--
--   SELECT has_table_privilege('anon', 'public.messages', 'SELECT') AS anon_lee;
--   -- Esperado: false
--
-- b) Las tres funciones y quien puede ejecutarlas:
--
--   SELECT p.proname,
--          has_function_privilege('anon', p.oid, 'EXECUTE')          AS anon_puede,
--          has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_puede
--   FROM pg_proc p
--   JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public'
--     AND p.proname IN ('send_student_message', 'get_student_messages',
--                       'mark_student_messages_read')
--   ORDER BY p.proname;
--   -- Esperado: anon_puede = true, auth_puede = true en las tres.
--
-- c) Smoke test con rollback. Necesita el qr_token de un alumno:
--
--   SELECT id, name, qr_token FROM public.students
--   WHERE deleted IS NOT TRUE AND qr_token IS NOT NULL LIMIT 1;
--
--   BEGIN;
--   SELECT public.send_student_message(
--     '<student_uuid>'::uuid, '<qr_token>', 'Hola, esto es un abono de $200', NULL);
--   SELECT jsonb_array_length(
--     public.get_student_messages('<student_uuid>'::uuid, '<qr_token>')) AS cantidad;
--   -- Esperado: cantidad >= 1
--
--   -- Token equivocado debe fallar:
--   SELECT public.get_student_messages('<student_uuid>'::uuid, 'token-falso');
--   -- Esperado: ERROR 'Token invalido'
--   ROLLBACK;
