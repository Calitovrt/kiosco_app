import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'supabase_service.dart';
import 'store_config.dart';

Future<void> exportPendingToExcel(BuildContext context) async {
  final data = await SupabaseService.instance.getAllPendingSales();

  if (data.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay deudas pendientes para exportar')),
      );
    }
    return;
  }

  final excel = Excel.createExcel();
  final sheet = excel['Deudores'];

  // ── STYLES ──
  final titleStyle = CellStyle(
    bold: true,
    fontSize: 16,
    fontColorHex: ExcelColor.fromHexString('FF1A1A2E'),
  );
  final headerStyle = CellStyle(
    bold: true,
    fontSize: 11,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: ExcelColor.fromHexString('FF4A90E2'),
  );
  final groupStyle = CellStyle(
    bold: true,
    fontSize: 12,
    fontColorHex: ExcelColor.fromHexString('FF1A1A2E'),
    backgroundColorHex: ExcelColor.fromHexString('FFE8F0FE'),
  );
  final subtotalStyle = CellStyle(
    bold: true,
    fontSize: 11,
    fontColorHex: ExcelColor.fromHexString('FF2563EB'),
  );
  final grandTotalStyle = CellStyle(
    bold: true,
    fontSize: 13,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: ExcelColor.fromHexString('FF1A1A2E'),
  );

  void setCell(String cell, dynamic value, [CellStyle? style]) {
    final c = sheet.cell(CellIndex.indexByString(cell));
    if (value is String) {
      c.value = TextCellValue(value);
    } else if (value is double) {
      c.value = TextCellValue('\$${value.toStringAsFixed(2)}');
    } else if (value is int) {
      c.value = IntCellValue(value);
    }
    if (style != null) c.cellStyle = style;
  }

  // ── ROW 1: TITLE ──
  setCell('A1', 'REPORTE DE DEUDORES', titleStyle);
  sheet.merge(CellIndex.indexByString('A1'), CellIndex.indexByString('G1'));

  // ── ROW 2: DATE ──
  final now = DateTime.now();
  final dateStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
  setCell('A2', 'Generado: $dateStr', CellStyle(fontSize: 10, fontColorHex: ExcelColor.fromHexString('666666')));
  sheet.merge(CellIndex.indexByString('A2'), CellIndex.indexByString('G2'));

  // ── ROW 4: HEADERS ──
  setCell('A4', StoreConfig.instance.entityName, headerStyle);
  setCell('B4', 'Producto', headerStyle);
  setCell('C4', 'Cant.', headerStyle);
  setCell('D4', 'Precio', headerStyle);
  setCell('E4', 'Total', headerStyle);
  setCell('F4', 'Abonado', headerStyle);
  setCell('G4', 'Restante', headerStyle);

  // ── SET COLUMN WIDTHS ──
  sheet.setColumnWidth(1, 20);
  sheet.setColumnWidth(2, 25);
  sheet.setColumnWidth(3, 8);
  sheet.setColumnWidth(4, 12);
  sheet.setColumnWidth(5, 12);
  sheet.setColumnWidth(6, 12);
  sheet.setColumnWidth(7, 12);

  // ── LOAD PENDING RECORDS with paid amounts ──
  final pendingRecords = await SupabaseService.instance.getAllPending();
  final paidByStudent = <String, double>{};
  final totalByStudent = <String, double>{};
  for (final p in pendingRecords) {
    final student = p['student'] as String? ?? '';
    final amount = (p['amount'] as num?)?.toDouble() ?? 0;
    final paid = (p['paid'] as num?)?.toDouble() ?? 0;
    paidByStudent[student] = paid;
    totalByStudent[student] = amount;
  }

  // ── DATA ──
  int row = 5;
  String? currentStudent;
  double studentSubtotal = 0;
  double grandTotal = 0;
  double grandRemaining = 0;

  for (int i = 0; i < data.length; i++) {
    final sale = data[i];
    final student = sale['student'] as String? ?? '';
    final product = sale['product'] as String? ?? '';
    final quantity = (sale['quantity'] as num?)?.toInt() ?? 1;
    final total = (sale['total'] as num?)?.toDouble() ?? 0;
    final unitPrice = quantity > 0 ? total / quantity : total;

    if (student != currentStudent) {
      if (currentStudent != null) {
        // Subtotal + paid + remaining row for previous student
        final paid = paidByStudent[currentStudent] ?? 0;
        final remaining = (totalByStudent[currentStudent] ?? studentSubtotal) - paid;
        setCell('D$row', '', subtotalStyle);
        setCell('E$row', studentSubtotal, subtotalStyle);
        setCell('F$row', paid, subtotalStyle);
        setCell('G$row', remaining, subtotalStyle);
        grandRemaining += remaining;
        row++;
      }
      studentSubtotal = 0;

      // Student name row
      setCell('A$row', student.toUpperCase(), groupStyle);
      sheet.merge(CellIndex.indexByString('A$row'), CellIndex.indexByString('G$row'));
      row++;
      currentStudent = student;
    }

    // Product row (Abonado/Restante shown per-student in subtotal)
    setCell('A$row', '');
    setCell('B$row', product);
    setCell('C$row', quantity);
    setCell('D$row', unitPrice);
    setCell('E$row', total);
    setCell('F$row', '');
    setCell('G$row', '');

    studentSubtotal += total;
    grandTotal += total;
    row++;
  }

  // Last student subtotal + paid + remaining
  if (currentStudent != null) {
    final paid = paidByStudent[currentStudent] ?? 0;
    final remaining = (totalByStudent[currentStudent] ?? studentSubtotal) - paid;
    setCell('D$row', '', subtotalStyle);
    setCell('E$row', studentSubtotal, subtotalStyle);
    setCell('F$row', paid, subtotalStyle);
    setCell('G$row', remaining, subtotalStyle);
    grandRemaining += remaining;
    row++;
  }

  // ── GRAND TOTAL ──
  row++;
  setCell('A$row', 'TOTAL GENERAL', grandTotalStyle);
  sheet.merge(CellIndex.indexByString('A$row'), CellIndex.indexByString('C$row'));
  setCell('D$row', '', grandTotalStyle);
  setCell('E$row', grandTotal, grandTotalStyle);
  setCell('F$row', grandTotal - grandRemaining, grandTotalStyle);
  setCell('G$row', grandRemaining, grandTotalStyle);

  // ── SAVE & SHARE ──
  final fileBytes = excel.save();
  if (fileBytes == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al generar el archivo')),
      );
    }
    return;
  }

  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/Deudores_${now.day}_${now.month}_$now.xlsx');
  await file.writeAsBytes(fileBytes);

  if (context.mounted) {
    await Share.shareXFiles(
      [XFile(file.path)],
      text: '${StoreConfig.instance.debtorTitle} - ${StoreConfig.instance.storeName}',
    );
  }
}

/// Una hoja del respaldo, ya resuelta a texto.
class BackupSheet {
  const BackupSheet({required this.headers, required this.rows});

  final List<String> headers;
  final List<List<String>> rows;
}

/// Arma el contenido del respaldo a partir de las filas crudas que devuelve
/// SupabaseService.
///
/// Es una funcion pura a proposito: el respaldo es el archivo que se abre
/// cuando ya se perdieron datos, asi que tiene que estar testeado.
///
/// Las claves deben coincidir con lo que devuelve el service layer:
/// `getSales()` y `getAllPendingSales()` aplanan las filas a snake_case
/// (`product`, `student`, `payment_method`, `paid_at`).
Map<String, BackupSheet> buildBackupSheets({
  required List<Map<String, dynamic>> sales,
  required List<Map<String, dynamic>> students,
  required List<Map<String, dynamic>> products,
  required List<Map<String, dynamic>> pending,
}) {
  return {
    'Ventas': BackupSheet(
      headers: const [
        'Producto',
        'Precio',
        'Cantidad',
        'Total',
        'Fecha',
        'Estudiante',
        'Método de pago',
      ],
      rows: sales.map((s) {
        final quantity = (s['quantity'] as num?)?.toInt() ?? 0;
        final total = (s['total'] as num?)?.toDouble() ?? 0;
        // `sales` guarda el total de la linea, no el precio unitario.
        final unitPrice = quantity > 0 ? total / quantity : 0;
        return [
          (s['product'] ?? '').toString(),
          unitPrice.toStringAsFixed(2),
          quantity.toString(),
          total.toStringAsFixed(2),
          (s['date'] ?? '').toString(),
          (s['student'] ?? '').toString(),
          (s['payment_method'] ?? '').toString(),
        ];
      }).toList(),
    ),
    'Alumnos': BackupSheet(
      headers: const ['Nombre'],
      rows: students.map((s) => [(s['name'] ?? '').toString()]).toList(),
    ),
    'Productos': BackupSheet(
      headers: const ['Nombre', 'Precio', 'Categoría', 'Icono'],
      rows: products
          .map((p) => [
                (p['name'] ?? '').toString(),
                (p['price'] ?? '').toString(),
                (p['category'] ?? '').toString(),
                (p['icon'] ?? '').toString(),
              ])
          .toList(),
    ),
    'Pendientes': BackupSheet(
      headers: const ['Estudiante', 'Producto', 'Monto', 'Fecha', 'Pagado'],
      rows: pending
          .map((p) => [
                (p['student'] ?? '').toString(),
                (p['product'] ?? '').toString(),
                ((p['total'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
                (p['date'] ?? '').toString(),
                p['paid_at'] != null ? 'Sí' : 'No',
              ])
          .toList(),
    ),
  };
}

Future<void> exportBackupToExcel(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Exportar respaldo'),
      content: const Text('Se va a exportar un archivo Excel con TODOS los datos del sistema (ventas, alumnos, productos, deudas). ¿Querés continuar?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Exportar')),
      ],
    ),
  );
  if (confirmed != true) return;

  final data = await Future.wait([
    SupabaseService.instance.getSales(),
    SupabaseService.instance.getStudents(),
    SupabaseService.instance.getProducts(),
    SupabaseService.instance.getAllPendingSales(),
  ]);
  final sales = data[0];
  final students = data[1];
  final products = data[2];
  final pending = data[3];

  final excel = Excel.createExcel();
  // Excel.createExcel() deja una hoja "Sheet1" vacia adelante.
  excel.delete('Sheet1');
  final sheets = buildBackupSheets(
    sales: sales,
    students: students,
    products: products,
    pending: pending,
  );

  for (final entry in sheets.entries) {
    final sheet = excel[entry.key];
    final h = entry.value.headers;
    final r = entry.value.rows;

    final headerStyle = CellStyle(
      fontColorHex: ExcelColor.fromHexString('FFFFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('FF4A90E2'),
      bold: true,
    );

    for (var col = 0; col < h.length; col++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
      cell.value = TextCellValue(h[col]);
      cell.cellStyle = headerStyle;
    }

    for (var i = 0; i < r.length; i++) {
      for (var col = 0; col < r[i].length; col++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: i + 1));
        final val = r[i][col];
        cell.value = TextCellValue(val.toString());
      }
    }
  }

  final fileBytes = excel.save();
  if (fileBytes == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al generar el archivo'), backgroundColor: Colors.red),
      );
    }
    return;
  }

  final now = DateTime.now();
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/Backup_${now.day}_${now.month}_${now.year}.xlsx');
  await file.writeAsBytes(fileBytes);

  if (context.mounted) {
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Backup - ${StoreConfig.instance.storeName}',
    );
  }
}
