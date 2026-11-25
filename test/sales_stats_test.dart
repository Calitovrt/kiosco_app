import 'package:flutter_test/flutter_test.dart';
import 'package:kiosco_app/services/sales_stats.dart';

void main() {
  group('computeSalesStats', () {
    test('los totales por recreo incluyen ventas cobradas, no solo la deuda',
        () {
      final sales = [
        {
          'product': 'Alfajor',
          'quantity': 1,
          'total': 100.0,
          'payment_method': 'Efectivo',
          'recreo': 'Recreo 1',
        },
        {
          'product': 'Jugo',
          'quantity': 1,
          'total': 250.0,
          'payment_method': 'Pendiente',
          'recreo': 'Recreo 1',
        },
        {
          'product': 'Alfajor',
          'quantity': 1,
          'total': 100.0,
          'payment_method': 'Yappy',
          'recreo': 'Recreo 2',
        },
      ];

      final stats = computeSalesStats(sales);

      expect(stats.recreo1, 350.0, reason: 'Recreo 1 = 100 cobrado + 250 fiado');
      expect(stats.recreo2, 100.0);
      expect(stats.efectivo, 100.0);
      expect(stats.yappy, 100.0);
      expect(stats.pendiente, 250.0);
      expect(stats.total, 450.0);
    });

    test('el producto mas vendido cuenta unidades, no filas', () {
      final sales = [
        {'product': 'Alfajor', 'quantity': 3, 'total': 300.0, 'payment_method': 'Efectivo'},
        {'product': 'Jugo', 'quantity': 1, 'total': 250.0, 'payment_method': 'Efectivo'},
        {'product': 'Jugo', 'quantity': 1, 'total': 250.0, 'payment_method': 'Efectivo'},
      ];

      final stats = computeSalesStats(sales);

      expect(stats.topProduct, 'Alfajor');
      expect(stats.topProductCount, 3);
    });

    test('un total null no rompe el calculo', () {
      final sales = [
        {'product': 'Alfajor', 'quantity': 1, 'total': null, 'payment_method': 'Efectivo'},
      ];

      expect(() => computeSalesStats(sales), returnsNormally);
      expect(computeSalesStats(sales).total, 0.0);
    });

    test('lista vacia devuelve ceros y sin producto destacado', () {
      final stats = computeSalesStats(const []);

      expect(stats.total, 0.0);
      expect(stats.topProduct, 'Ninguno');
      expect(stats.topProductCount, 0);
      expect(stats.totalTransactions, 0);
    });
  });
}
