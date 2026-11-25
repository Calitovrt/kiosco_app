import 'dart:math';

/// Genera una referencia de operacion (UUID v4) que viaja con el carrito.
///
/// La app la manda en `p_client_ref`: si el mismo carrito se reintenta
/// despues de un timeout, el servidor reconoce la referencia y no vuelve a
/// insertar la venta. Vive fuera del State y acepta un `Random` inyectable
/// para poder testearla.
String newClientRef([Random? random]) {
  final rnd = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));

  // Version 4 y variante RFC 4122.
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

/// Huella estable de un carrito: dos listas con los mismos productos y
/// cantidades producen la misma huella, sin importar el orden.
///
/// Se usa para decidir si la referencia de operacion guardada todavia
/// corresponde al carrito actual, o si hay que generar una nueva.
String cartSignature(List<Map<String, dynamic>> items) {
  final parts = items.map((e) => '${e['id']}:${e['quantity']}').toList()..sort();
  return parts.join('|');
}
