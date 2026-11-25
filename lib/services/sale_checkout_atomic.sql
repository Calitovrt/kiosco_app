-- =====================================================
-- CHECKOUT ATOMICO DEL MOSTRADOR - kiosco_app
-- Archivo #13 de SQL_APPLY_ORDER.md
--
-- Correr DESPUES de student_activation.sql y
-- checkout_hardening.sql.
--
-- La app nueva llama a public.sale_checkout(). Si este archivo no
-- corrio, la pantalla de Ventas falla con
-- "Could not find the function public.sale_checkout".
-- =====================================================
--
-- QUE ARREGLA
--
-- completeSale() hacia tres escrituras sueltas desde el cliente:
--   1. INSERT de las filas de sales
--   2. UPDATE del stock de cada producto (valor absoluto)
--   3. INSERT en pending si era fiado
--
-- Cualquier corte en el medio dejaba el sistema mintiendo:
--   - falla (3): la deuda queda en sales pero no en pending, o sea
--     plata que no aparece en la pantalla Pendientes.
--   - falla (2): la venta existe y el stock no bajo.
--   - dos terminales vendiendo el mismo producto se pisan el stock
--     porque cada una escribe un absoluto calculado de su snapshot.
--
-- Ahora todo pasa en una sola transaccion del lado del servidor, el
-- stock se decrementa con "stock = stock - qty" (atomico), y un
-- reintento del mismo carrito no duplica nada gracias a client_ref.
-- =====================================================

-- 1. Referencia de idempotencia del cliente.
--    La app genera un UUID por carrito y lo reusa en los reintentos.
ALTER TABLE public.sales
  ADD COLUMN IF NOT EXISTS client_ref UUID;

-- client_ref identifica la OPERACION, no la fila: un carrito de 3 productos
-- escribe 3 filas con la misma referencia. Por eso el indice NO puede ser
-- unico (era el bug: la segunda linea del carrito violaba el indice y abortaba
-- la venta entera). La idempotencia la garantiza el EXISTS de la funcion.
DROP INDEX IF EXISTS public.sales_client_ref_key;
CREATE INDEX IF NOT EXISTS sales_client_ref_idx
  ON public.sales (client_ref)
  WHERE client_ref IS NOT NULL;

-- 2. La transaccion del mostrador.
CREATE OR REPLACE FUNCTION public.sale_checkout(
  p_client_ref UUID,
  p_student_id UUID,
  p_payment_method TEXT,
  p_recreo TEXT,
  p_date TEXT,
  p_time TEXT,
  p_cart_items JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_item JSONB;
  v_product_id UUID;
  v_qty INT;
  v_price NUMERIC;
  v_line_total NUMERIC;
  v_total NUMERIC := 0;
  v_is_fiado BOOLEAN;
BEGIN
  -- Autorizacion. Si sabemos quien llama (auth.uid() no es null) tiene
  -- que ser admin. Si es el owner (SQL Editor, auth.uid() null) se
  -- confia en los grants: anon no tiene EXECUTE sobre esta funcion.
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  IF p_client_ref IS NULL THEN
    RAISE EXCEPTION 'Referencia de operacion requerida';
  END IF;

  -- Idempotencia: si este carrito ya se cobro, devolver el resultado
  -- anterior en vez de insertar una venta duplicada. Cubre el caso de
  -- timeout donde el commit ocurrio pero la respuesta no llego.
  IF EXISTS (SELECT 1 FROM public.sales WHERE client_ref = p_client_ref) THEN
    SELECT COALESCE(SUM(total), 0) INTO v_total
    FROM public.sales WHERE client_ref = p_client_ref;
    RETURN jsonb_build_object('status', 'duplicate', 'total', v_total);
  END IF;

  IF p_student_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.students
    WHERE id = p_student_id AND deleted IS NOT TRUE
  ) THEN
    RAISE EXCEPTION 'Alumno no encontrado';
  END IF;

  IF p_cart_items IS NULL
     OR jsonb_typeof(p_cart_items) <> 'array'
     OR jsonb_array_length(p_cart_items) = 0 THEN
    RAISE EXCEPTION 'Carrito vacio';
  END IF;

  -- El kiosco no puede fechar la venta a mano: se compara contra el dia
  -- local. Mismo criterio que student_checkout.
  IF p_date IS DISTINCT FROM
     to_char((now() AT TIME ZONE 'America/Bogota')::date, 'YYYY-MM-DD') THEN
    RAISE EXCEPTION 'Fecha invalida';
  END IF;

  v_is_fiado := COALESCE(p_payment_method, '') ILIKE '%pendiente%';

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_cart_items)
  LOOP
    v_product_id := (v_item->>'product_id')::UUID;
    v_qty := (v_item->>'quantity')::INT;

    IF v_qty IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'Cantidad invalida';
    END IF;
    IF v_qty > 50 THEN
      RAISE EXCEPTION 'Cantidad fuera de rango';
    END IF;

    -- El precio lo pone la base, no el cliente.
    SELECT price INTO v_price FROM public.products WHERE id = v_product_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Producto no encontrado: %', v_product_id;
    END IF;

    -- Decremento atomico: si otra terminal ya se llevo el stock, esta
    -- linea no actualiza nada y la venta entera aborta.
    UPDATE public.products SET stock = stock - v_qty
    WHERE id = v_product_id AND stock >= v_qty;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Stock insuficiente';
    END IF;

    v_line_total := v_price * v_qty;
    v_total := v_total + v_line_total;

    INSERT INTO public.sales (
      student_id, product_id, quantity, total, payment_method,
      paid_at, prepared_at, date, time, recreo, client_ref
    ) VALUES (
      p_student_id,
      v_product_id,
      v_qty,
      v_line_total,
      p_payment_method,
      -- paid_at: null si es fiado (sigue impago).
      -- prepared_at: SIEMPRE now(). Un fiado de mostrador ya se entrego: el
      -- alumno se fue con el producto. Si queda en null aparece en "Pedidos
      -- del dia" pidiendo una accion que no existe (marcarlo "Pendiente
      -- fiado" volveria a sumar la deuda). La deuda vive en `pending`.
      CASE WHEN v_is_fiado THEN NULL ELSE now() END,
      now(),
      p_date,
      p_time,
      p_recreo,
      p_client_ref
    );
  END LOOP;

  -- Una sola fila de deuda por alumno, acumulando (misma semantica que
  -- el viejo upsert_pending). pending.student_id es UUID: se pasa sin cast.
  IF v_is_fiado THEN
    INSERT INTO public.pending (student_id, amount, paid, paid_at, created_at)
    VALUES (p_student_id, v_total, 0, NULL, now())
    ON CONFLICT (student_id) DO UPDATE SET
      amount  = public.pending.amount + EXCLUDED.amount,
      paid_at = NULL;
  END IF;

  RETURN jsonb_build_object('status', 'ok', 'total', v_total);
END;
$$;

-- 3. Solo el admin autenticado puede cobrar. anon queda afuera.
REVOKE ALL ON FUNCTION public.sale_checkout(UUID, UUID, TEXT, TEXT, TEXT, TEXT, JSONB)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sale_checkout(UUID, UUID, TEXT, TEXT, TEXT, TEXT, JSONB)
  TO authenticated;

-- =====================================================
-- VERIFICACION
-- =====================================================
--
-- a) La funcion y el grant existen:
--
--   SELECT p.proname,
--          has_function_privilege('anon', p.oid, 'EXECUTE')          AS anon_puede,
--          has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_puede
--   FROM pg_proc p
--   JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public' AND p.proname = 'sale_checkout';
--
--   Esperado: anon_puede = false, auth_puede = true.
--
-- b) Smoke test con rollback (no deja datos). Usa la primera alumna y el
--    primer producto con stock. Se puede correr desde el SQL Editor
--    porque ahi auth.uid() es null y la funcion lo permite:
--
--   BEGIN;
--
--   SELECT public.sale_checkout(
--     gen_random_uuid(),
--     (SELECT id FROM public.students WHERE deleted IS NOT TRUE LIMIT 1),
--     'Efectivo',
--     'Recreo 1',
--     to_char((now() AT TIME ZONE 'America/Bogota')::date, 'YYYY-MM-DD'),
--     to_char((now() AT TIME ZONE 'America/Bogota'), 'HH24:MI'),
--     jsonb_build_array(jsonb_build_object(
--       'product_id', (SELECT id FROM public.products WHERE stock > 0 LIMIT 1),
--       'quantity', 1))
--   );
--
--   -- Reintento con la MISMA referencia: tiene que devolver
--   -- status = 'duplicate' y no insertar otra fila.
--   SELECT count(*) FROM public.sales WHERE client_ref IS NOT NULL;
--
--   ROLLBACK;
--
-- c) Test de stock insuficiente: debe abortar la venta entera.
--
--   BEGIN;
--   SELECT public.sale_checkout(
--     gen_random_uuid(),
--     (SELECT id FROM public.students WHERE deleted IS NOT TRUE LIMIT 1),
--     'Efectivo', 'Recreo 1',
--     to_char((now() AT TIME ZONE 'America/Bogota')::date, 'YYYY-MM-DD'),
--     '10:00',
--     jsonb_build_array(jsonb_build_object(
--       'product_id', (SELECT id FROM public.products WHERE stock > 0 LIMIT 1),
--       'quantity', 999))
--   );
--   -- Esperado: ERROR 'Cantidad fuera de rango'
--   ROLLBACK;
--
-- d) Despues de aplicar, verificar que no quedo una sobrecarga vieja:
--
--   SELECT proname, count(*) FROM pg_proc
--   WHERE pronamespace = 'public'::regnamespace
--   GROUP BY 1 HAVING count(*) > 1;
