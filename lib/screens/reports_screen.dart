import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import '../services/sales_stats.dart';
import '../services/date_utils.dart';
import '../services/responsive.dart';
import '../services/store_config.dart';

class ReportsScreen extends StatefulWidget {

  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() =>
      _ReportsScreenState();
}

class _ReportsScreenState
    extends State<ReportsScreen> {

  // =====================================================
  // VARIABLES
  // =====================================================

  double totalSales = 0;
  String selectedFilter = 'Hoy';

  double efectivoTotal = 0;

  double yappyTotal = 0;

  double pendienteTotal = 0;
  double recreo1Total = 0;

  double recreo2Total = 0;
  int totalTransactions = 0;
  String topProduct = '';

  int topProductCount = 0;

  List<Map<String, dynamic>> sales = [];

  List<Map<String, dynamic>> _allSales = [];

  StreamSubscription? _salesSub;

  // =====================================================
  // INIT
  // =====================================================

  @override
  void initState() {
    super.initState();
    _salesSub = SupabaseService.instance
        .streamSales()
        .listen((data) {
      _allSales = data;
      _computeReports();
    })
      ..onError((e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error en reportes: $e'), backgroundColor: Colors.red),
          );
        }
      });
  }

  @override
  void dispose() {
    _salesSub?.cancel();
    super.dispose();
  }

  void _computeReports() {
    var salesData = _allSales.where((sale) {
      final dateText = sale['date'] ?? '';
      final now = DateTime.now();

      if (selectedFilter == 'Hoy') {
        final todayStr =
            toISODate(now);
        return dateText == todayStr;
      }

      if (selectedFilter == 'Semana') {
        final weekAgo = DateTime.now()
            .subtract(const Duration(days: 6))
            .toIso8601String()
            .substring(0, 10);
        return dateText.compareTo(weekAgo) >= 0;
      }

      if (selectedFilter == 'Mes') {
        final monthStr =
            '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
        return dateText.startsWith(monthStr);
      }

      return true;
    }).toList();

    final stats = computeSalesStats(salesData);

    setState(() {
      this.sales = salesData;
      totalSales = stats.total;
      efectivoTotal = stats.efectivo;
      yappyTotal = stats.yappy;
      pendienteTotal = stats.pendiente;
      recreo1Total = stats.recreo1;
      recreo2Total = stats.recreo2;
      totalTransactions = stats.totalTransactions;
      topProduct = stats.topProduct;
      topProductCount = stats.topProductCount;
    });
  }

  // =====================================================
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor:
      Theme.of(context).scaffoldBackgroundColor,


      body: SingleChildScrollView(


        padding: EdgeInsets.all(
          R.sp(context, 24),
        ),

        child: Column(

          crossAxisAlignment:
          CrossAxisAlignment.start,

          children: [
            SizedBox(
              height: R.sp(context, 50),

              child: ListView(
                scrollDirection: Axis.horizontal,

                children: [

                  filterButton(
                    'Hoy',
                    selectedFilter == 'Hoy',
                    () {
                      setState(() {
                        selectedFilter = 'Hoy';
                      });
                      _computeReports();
                    },
                  ),

                  filterButton(
                    'Semana',
                    selectedFilter == 'Semana',
                        () {
                      setState(() {
                        selectedFilter = 'Semana';
                      });
                      _computeReports();
                    },
                  ),

                  filterButton(
                    'Mes',
                    selectedFilter == 'Mes',
                        () {
                      setState(() {
                        selectedFilter = 'Mes';
                      });
                      _computeReports();
                    },
                  ),



                ],
              ),
            ),
            SizedBox(height: R.sp(context, 20)),

            // =================================================
            // TITLE
            // =================================================

            Text(

              'Reportes',

              style: TextStyle(

                fontSize: R.fs(context, 38),

                fontWeight:
                FontWeight.bold,

                color:
                Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),

            SizedBox(height: R.sp(context, 10)),

            Text(

              StoreConfig.instance.appSubtitle,

              style: TextStyle(

                fontSize: R.fs(context, 18),

                color:
                Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
              ),
            ),

            SizedBox(height: R.sp(context, 30)),

            // =================================================
            // TOP CARDS (responsive wrap)
            // =================================================

            // =================================================
            // TOP CARDS: tarjeta principal + grilla 2x2
            // =================================================

            _heroCard(
              title: 'Ventas Totales',
              value: '\$${totalSales.toStringAsFixed(2)}',
              color: Colors.blue,
              icon: Icons.attach_money,
            ),

            SizedBox(height: R.sp(context, 16)),

            Row(
              children: [
                Expanded(
                  child: _miniCard(
                    title: 'Transacciones',
                    value: '$totalTransactions',
                    color: Colors.orange,
                    icon: LucideIcons.receipt,
                  ),
                ),
                SizedBox(width: R.sp(context, 16)),
                Expanded(
                  child: _miniCard(
                    title: 'Pendientes',
                    value: '\$${pendienteTotal.toStringAsFixed(2)}',
                    color: Colors.red,
                    icon: Icons.warning_rounded,
                  ),
                ),
              ],
            ),

            SizedBox(height: R.sp(context, 16)),

            Row(
              children: [
                Expanded(
                  child: _miniCard(
                    title: 'Recreo 1',
                    value: '\$${recreo1Total.toStringAsFixed(2)}',
                    color: Colors.purple,
                    icon: Icons.schedule,
                  ),
                ),
                SizedBox(width: R.sp(context, 16)),
                Expanded(
                  child: _miniCard(
                    title: 'Recreo 2',
                    value: '\$${recreo2Total.toStringAsFixed(2)}',
                    color: Colors.teal,
                    icon: LucideIcons.clock,
                  ),
                ),
              ],
            ),

            // =================================================
            // CHART
            // =================================================

            Container(

              padding: EdgeInsets.all(
                R.sp(context, 24),
              ),

              decoration:
              BoxDecoration(

                color:
                Theme.of(context).cardColor,

                borderRadius:
                BorderRadius.circular(
                  28,
                ),

                boxShadow: [

                  BoxShadow(

                    color: Colors.black
                        .withValues(alpha: 
                      0.05,
                    ),

                    blurRadius: 18,

                    offset:
                    const Offset(
                      0,
                      8,
                    ),
                  ),
                ],
              ),

              child: Column(

                crossAxisAlignment:
                CrossAxisAlignment
                    .start,

                children: [

                  Text(

                    'Métodos de Pago',

                    style: TextStyle(

                      fontSize: R.fs(context, 26),

                      fontWeight:
                      FontWeight.bold,

                      color:
                      Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),

                  SizedBox(
                    height: R.sp(context, 30),
                  ),

                  SizedBox(

                    height: R.sp(context, 220),

                    child: BarChart(

                      BarChartData(

                        alignment:
                        BarChartAlignment
                            .spaceAround,

                        minY: 0,

                        maxY: _chartMaxY,

                        barTouchData: BarTouchData(enabled: false),

                        barGroups: [

                          BarChartGroupData(

                            x: 0,

                            barRods: [

                              BarChartRodData(

                                toY:
                                efectivoTotal,

                                width: 32,

                                borderRadius:
                                BorderRadius
                                    .circular(
                                  12,
                                ),

                                color:
                                Colors.green,
                              ),
                            ],
                          ),

                          BarChartGroupData(

                            x: 1,

                            barRods: [

                              BarChartRodData(

                                toY:
                                yappyTotal,

                                width: 32,

                                borderRadius:
                                BorderRadius
                                    .circular(
                                  12,
                                ),

                                color:
                                Colors.blue,
                              ),
                            ],
                          ),

                          BarChartGroupData(

                            x: 2,

                            barRods: [

                              BarChartRodData(

                                toY:
                                pendienteTotal,

                                width: 32,

                                borderRadius:
                                BorderRadius
                                    .circular(
                                  12,
                                ),

                                color:
                                Colors.red,
                              ),
                            ],
                          ),
                        ],
                        titlesData: FlTitlesData(

                          leftTitles: AxisTitles(

                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 52,
                              interval: _chartInterval,
                              getTitlesWidget: (value, meta) {
                                if (value == meta.max) {
                                  return const SizedBox.shrink();
                                }
                                return Text(
                                  '\$${value.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontSize: R.fs(context, 11),
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.color
                                        ?.withValues(alpha: 0.6),
                                  ),
                                );
                              },
                            ),
                          ),

                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: false,
                            ),
                          ),

                          topTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: false,
                            ),
                          ),

                          bottomTitles: AxisTitles(

                            sideTitles: SideTitles(

                              showTitles: true,

                              reservedSize: 35,

                              getTitlesWidget:
                                  (value, meta) {

                                switch (value.toInt()) {

                                  case 0:
                                    return const Text(
                                      'Efectivo',
                                    );

                                  case 1:
                                    return const Text(
                                      'Yappy',
                                    );

                                  case 2:
                                    return const Text(
                                      'Pendiente',
                                    );
                                }

                                return const Text('');
                              },
                            ),
                          ),
                        ),

                        borderData:
                        FlBorderData(
                          show: false,
                        ),

                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: _chartInterval,
                          getDrawingHorizontalLine: (value) => FlLine(
                            color: Theme.of(context)
                                .dividerColor
                                .withValues(alpha: 0.25),
                            strokeWidth: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Container(

              padding: EdgeInsets.all(
                R.sp(context, 24),
              ),

              decoration:
              BoxDecoration(

                color:
                Theme.of(context).cardColor,

                borderRadius:
                BorderRadius.circular(
                  28,
                ),

                boxShadow: [
                  BoxShadow(

                    color: Colors.black
                        .withValues(alpha:
                      0.05,
                    ),

                    blurRadius: 18,

                    offset:
                    const Offset(
                      0,
                      8,
                    ),
                  ),
                ],
              ),

              child: Column(

                crossAxisAlignment:
                CrossAxisAlignment
                    .start,

                children: [

                  Text(

                    'Últimas Ventas',

                    style: TextStyle(

                      fontSize: R.fs(context, 26),

                      fontWeight:
                      FontWeight.bold,

                      color:
                      Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),

                  SizedBox(
                    height: R.sp(context, 20),
                  ),

                  sales.isEmpty

                      ? Center(

                    child: Padding(

                      padding: EdgeInsets.all(
                        R.sp(context, 30),
                      ),

                      child: Text(

                        'No hay ventas',

                        style: TextStyle(
                          fontSize: R.fs(context, 18),
                        ),
                      ),
                    ),
                  )

                      : Column(
                    children: sales.map((sale) {
                      final isPending = (sale['payment_method'] ?? '')
                          .toString().toLowerCase().contains('pendiente');
                      return Container(
                        margin: EdgeInsets.only(
                          bottom: R.sp(context, 16),
                        ),
                        padding: EdgeInsets.all(
                          R.sp(context, 20),
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(R.sp(context, 14)),
                              decoration: BoxDecoration(
                                color: (isPending ? Colors.orange : Colors.green).withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isPending ? LucideIcons.clock : LucideIcons.check,
                                color: isPending ? Colors.orange : Colors.green,
                              ),
                            ),
                            SizedBox(width: R.sp(context, 18)),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          sale['student']?.toString() ?? '',
                                          style: TextStyle(
                                            fontSize: R.fs(context, 20),
                                            fontWeight: FontWeight.bold,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isPending)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Text(
                                            'Pendiente',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.orange,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  SizedBox(height: R.sp(context, 4)),
                                  Text(
                                    '${sale['product'] ?? ''}',
                                    style: TextStyle(
                                      color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                                    ),
                                  ),
                                  Text(
                                    '${sale['date'] ?? ''} · ${formatTime(sale['time'])}',
                                    style: TextStyle(
                                      fontSize: R.fs(context, 12),
                                      color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.4),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '\$${((sale['total'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: R.fs(context, 22),
                                fontWeight: FontWeight.bold,
                                color: isPending
                                    ? Colors.orange
                                    : (Theme.of(context).brightness == Brightness.dark
                                        ? Colors.green.shade300
                                        : Colors.green),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget filterButton(
      String title,
      bool isSelected,
      VoidCallback onTap,
      ) {
    return GestureDetector(
      onTap: onTap,

      child: Container(
        margin: EdgeInsets.only(right: R.sp(context, 12)),

        padding: EdgeInsets.symmetric(
          horizontal: R.sp(context, 24),
          vertical: R.sp(context, 14),
        ),

        decoration: BoxDecoration(
          color:
          isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).cardColor,

          borderRadius:
          BorderRadius.circular(18),
        ),

        child: Text(
          title,

          style: TextStyle(
            color:
            isSelected
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).textTheme.bodyLarge?.color,

            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
  // =====================================================
  // MINI CARD (compact, wrap-friendly)
  // =====================================================

  /// Escala del eje Y según el dato real, no un +20 arbitrario.
  /// Con todo en 0 devuelve 10 para que el eje tenga sentido igual.
  double get _chartMaxY {
    final maxValue = [efectivoTotal, yappyTotal, pendienteTotal]
        .reduce((a, b) => a > b ? a : b);
    if (maxValue <= 0) return 10;
    return (maxValue * 1.25).ceilToDouble();
  }

  double get _chartInterval => _chartMaxY / 4;

  Widget _heroCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    final muted = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.color
        ?.withValues(alpha: 0.6);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(R.sp(context, 20)),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(R.sp(context, 12)),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: R.sp(context, 28)),
          ),
          SizedBox(width: R.sp(context, 14)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: R.fs(context, 13),
                    color: muted,
                  ),
                ),
                SizedBox(height: R.sp(context, 4)),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: R.fs(context, 34),
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: EdgeInsets.all(R.sp(context, 14)),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(R.sp(context, 8)),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: R.sp(context, 22)),
          ),
          SizedBox(width: R.sp(context, 10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: R.fs(context, 20),
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                SizedBox(height: R.sp(context, 2)),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: R.fs(context, 12),
                    color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}