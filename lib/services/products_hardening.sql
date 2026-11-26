-- =====================================================
-- PRODUCTOS: ventana publica con columnas explicitas
-- Archivo #16 de SQL_APPLY_ORDER.md
--
-- Correr DESPUES de search_hardening.sql
-- =====================================================
--
-- EL PROBLEMA
--
-- `products_anon_read` deja que anon lea la tabla entera. Hoy solo hay
-- datos de catalogo (nombre, precio, stock, icono), asi que no parece
-- grave. Pero "leer la tabla" incluye TODA columna presente y futura.
--
-- Ejemplo: el dia que se agregue `cost` (lo que cuesta comprarlo) o
-- `supplier`, no hay que tocar ninguna policy para que se publique:
-- la policy ya dice "anon puede leer products".
--
-- Verificado 2026-11-25: GET /rest/v1/products con el anon key
-- devolvia filas con 10 columnas: id, name, price, stock, category_id,
-- created_at, updated_at, category, icon, image_url.
--
-- SE APLICA EN DOS FASES
--
-- La app del alumno pasa a leer la vista. Mientras queden celulares con
-- una version vieja (que lee la tabla directo), borrar la policy les
-- vaciaria el catalogo. Por eso:
--
--   FASE 1 (ahora): crear la vista. La policy se queda.
--   FASE 2 (cuando todos actualicen): borrar la policy.
--
-- La app nueva ademas tiene fallback: si la vista no existe, lee la
-- tabla. Asi se puede instalar antes de correr este archivo.
-- =====================================================

-- =====================================================
-- FASE 1 — la ventana publica
-- =====================================================

DROP VIEW IF EXISTS public.products_public;

CREATE VIEW public.products_public AS
SELECT
  id,
  name,
  price,
  stock,
  icon,
  category,
  image_url
FROM public.products;

GRANT SELECT ON public.products_public TO anon, authenticated;

-- =====================================================
-- FASE 2 — cerrar la tabla (NO correr todavia)
-- =====================================================
--
-- Descomentar cuando ningun celular del kiosco use una version anterior
-- a la 1.6.3. Si se corre antes, esas versiones ven el catalogo vacio.
--
-- DROP POLICY IF EXISTS products_anon_read ON public.products;
--
-- Para saber si ya se puede: revisar en Supabase Auth > Users que no haya
-- sesiones viejas, o simplemente esperar unos dias despues de avisar.
-- =====================================================

-- =====================================================
-- VERIFICACION
-- =====================================================
--
-- a) La vista existe y devuelve 7 columnas:
--
--   SELECT * FROM public.products_public LIMIT 1;
--
-- b) Desde afuera, con el anon key:
--
--   GET /rest/v1/products_public?select=*&limit=1 -> filas
--   GET /rest/v1/products?select=*&limit=1        -> sigue devolviendo
--        (hasta que se corra la FASE 2)
--
-- c) El kiosco (admin autenticado) sigue viendo la tabla completa.
--
-- OJO: si en el futuro hace falta una columna nueva para el alumno, hay
-- que agregarla a la vista explicitamente. Eso es el punto: que sea una
-- decision, no un accidente.
