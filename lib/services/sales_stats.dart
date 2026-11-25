/// Agregaciones de ventas que alimentan la pantalla de Reportes.
///
/// Vive fuera del `State` a proposito: es logica pura sobre las filas que
/// devuelve SupabaseService, asi que se puede testear sin widget tree ni red.
class SalesStats {
  const SalesStats({
    required this.total,
    required this.efectivo,
    required this.yappy,
    required this.pendiente,
    required this.recreo1,
    required this.recreo2,
    required this.topProduct,
    required this.topProductCount,
    required this.totalTransactions,
  });

  /// Suma de todas las ventas del filtro activo, incluidas las fiadas.
  final double total;
  final double efectivo;
  final double yappy;
  final double pendiente;

  /// Ventas de cada recreo, cobradas o fiadas.
  final double recreo1;
  final double recreo2;

  final String topProduct;
  final int topProductCount;
  final int totalTransactions;
}

SalesStats computeSalesStats(List<Map<String, dynamic>> sales) {
  double total = 0;
  double efectivo = 0;
  double yappy = 0;
  double pendiente = 0;
  double recreo1 = 0;
  double recreo2 = 0;

  // Se acumulan unidades por producto, no filas: dos ventas de 1 unidad no
  // pueden empatar con una sola venta de 3.
  final unitsByProduct = <String, int>{};
  String topProduct = 'Ninguno';
  int topProductCount = 0;

  for (final sale in sales) {
    final product = (sale['product'] as String? ?? '').trim();
    if (product.isNotEmpty) {
      final quantity = (sale['quantity'] as num?)?.toInt() ?? 1;
      final units = (unitsByProduct[product] ?? 0) + quantity;
      unitsByProduct[product] = units;
      if (units > topProductCount) {
        topProductCount = units;
        topProduct = product;
      }
    }

    final amount = (sale['total'] as num?)?.toDouble() ?? 0;
    total += amount;

    switch ((sale['payment_method'] as String? ?? '').trim().toLowerCase()) {
      case 'efectivo':
        efectivo += amount;
      case 'yappy':
        yappy += amount;
      case 'pendiente':
        pendiente += amount;
    }

    // Recreo es un eje independiente del metodo de pago: suma todas las ventas
    // de ese recreo. Antes vivia anidado dentro del bloque de fiado, asi que
    // las tarjetas solo mostraban deuda impaga.
    switch ((sale['recreo'] as String? ?? '').trim()) {
      case 'Recreo 1':
        recreo1 += amount;
      case 'Recreo 2':
        recreo2 += amount;
    }
  }

  return SalesStats(
    total: total,
    efectivo: efectivo,
    yappy: yappy,
    pendiente: pendiente,
    recreo1: recreo1,
    recreo2: recreo2,
    topProduct: topProduct,
    topProductCount: topProductCount,
    totalTransactions: sales.length,
  );
}
