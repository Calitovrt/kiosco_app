import 'package:flutter_test/flutter_test.dart';
import 'package:kiosco_app/services/exporter.dart';

/// Las filas que llegan aca son las que devuelve SupabaseService: claves
/// snake_case y aplanadas (`product`, `student`, `payment_method`, `paid_at`).
/// El backup anterior leia camelCase (`productName`, `studentName`, ...) y
/// exportaba la mitad de las columnas vacias.
void main() {
  group('buildBackupSheets', () {
    test('la hoja Ventas lee las claves reales de getSales()', () {
      final sheets = buildBackupSheets(
        sales: [
          {
            'product': 'Alfajor',
            'quantity': 2,
            'total': 200.0,
            'date': '2026-11-24',
            'student': 'Alumno Uno',
            'payment_method': 'Efectivo',
            'paid_at': '2026-11-24T10:05:00.000',
          },
        ],
        students: [
          {'name': 'Alumno Uno'},
        ],
        products: [
          {'name': 'Alfajor', 'price': 100.0, 'category': 'Golosinas', 'icon': 'cookie'},
        ],
        pending: [],
      );

      final ventas = sheets['Ventas']!;
      expect(ventas.rows, hasLength(1));

      final row = ventas.rows.first;
      expect(row[0], 'Alfajor', reason: 'Producto');
      expect(row[1], '100.00', reason: 'Precio unitario derivado de total/cantidad');
      expect(row[2], '2', reason: 'Cantidad');
      expect(row[3], '200.00', reason: 'Total');
      expect(row[4], '2026-11-24', reason: 'Fecha');
      expect(row[5], 'Alumno Uno', reason: 'Estudiante');
      expect(row[6], 'Efectivo', reason: 'Metodo de pago');
    });

    test('la hoja Pendientes lee filas aplanadas, no camelCase', () {
      final sheets = buildBackupSheets(
        sales: [],
        students: [],
        products: [],
        pending: [
          {
            'student': 'Alumno Dos',
            'product': 'Jugo',
            'total': 250.0,
            'date': '2026-11-24',
            'paid_at': null,
          },
        ],
      );

      final row = sheets['Pendientes']!.rows.first;
      expect(row[0], 'Alumno Dos', reason: 'Estudiante');
      expect(row[1], 'Jugo', reason: 'Producto');
      expect(row[2], '250.00', reason: 'Monto');
      expect(row[3], '2026-11-24', reason: 'Fecha');
      expect(row[4], 'No', reason: 'Pagado');
    });

    test('filas incompletas no rompen la generacion del respaldo', () {
      final sheets = buildBackupSheets(
        sales: [
          {'quantity': null, 'total': null},
        ],
        students: [],
        products: [],
        pending: [],
      );

      expect(() => sheets['Ventas']!.rows, returnsNormally);
      expect(sheets['Ventas']!.rows.first[2], '0', reason: 'Cantidad ausente');
      expect(sheets['Ventas']!.rows.first[3], '0.00', reason: 'Total ausente');
    });

    test('todas las hojas esperadas existen', () {
      final sheets = buildBackupSheets(
        sales: [],
        students: [],
        products: [],
        pending: [],
      );

      expect(sheets.keys, containsAll(['Ventas', 'Alumnos', 'Productos', 'Pendientes']));
    });
  });
}
