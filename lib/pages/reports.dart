import 'dart:math';

import 'package:flutter/material.dart';
import 'package:pos_app/utils/currency.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  static const Map<String, Map<String, dynamic>> _reportData = {
    'Today': {
      'revenue': 1520.50,
      'sales': 24,
      'change': 12,
      'trendUp': true,
      'categories': {'Food': 45, 'Drinks': 30, 'Supplies': 25},
      'topProducts': [
        {'name': 'Twinpack Nescafe', 'qty': 8},
        {'name': 'Lucky Pancit Cantoon', 'qty': 5},
        {'name': 'Sardines', 'qty': 4},
      ],
    },
    'Weekly': {
      'revenue': 10240.80,
      'sales': 142,
      'change': 8,
      'trendUp': false,
      'categories': {'Food': 40, 'Drinks': 35, 'Supplies': 25},
      'topProducts': [
        {'name': 'Lucky Mae', 'qty': 28},
        {'name': 'Twinpack Nescafe', 'qty': 24},
        {'name': 'Birds Tree', 'qty': 18},
      ],
    },
    'Monthly': {
      'revenue': 41280.20,
      'sales': 610,
      'change': 17,
      'trendUp': true,
      'categories': {'Food': 50, 'Drinks': 28, 'Supplies': 22},
      'topProducts': [
        {'name': 'Twinpack Nescafe', 'qty': 92},
        {'name': 'Lucky Mae', 'qty': 78},
        {'name': 'Lucky Pancit Cantoon', 'qty': 64},
      ],
    },
  };

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Reports',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Review performance for today, weekly and monthly sales.',
                      style: TextStyle(fontSize: 14, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Container(
                  padding: const EdgeInsets.all(4.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: TabBar(
                    indicator: BoxDecoration(
                      color: Colors.blue.shade700,
                      borderRadius: BorderRadius.circular(14.0),
                    ),
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.black87,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    indicatorPadding: const EdgeInsets.symmetric(
                      horizontal: 4.0,
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelPadding: const EdgeInsets.symmetric(vertical: 12.0),
                    tabs: const [
                      Tab(text: 'Today'),
                      Tab(text: 'Weekly'),
                      Tab(text: 'Monthly'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: TabBarView(
                  children: _reportData.keys.map((label) {
                    final data = _reportData[label]!;
                    return _ReportTabView(
                      label: label,
                      revenue: data['revenue'] as double,
                      sales: data['sales'] as int,
                      change: data['change'] as int,
                      trendUp: data['trendUp'] as bool,
                      categories: Map<String, int>.from(
                        data['categories'] as Map,
                      ),
                      topProducts: List<Map<String, dynamic>>.from(
                        data['topProducts'] as List,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportTabView extends StatelessWidget {
  final String label;
  final double revenue;
  final int sales;
  final int change;
  final bool trendUp;
  final Map<String, int> categories;
  final List<Map<String, dynamic>> topProducts;

  const _ReportTabView({
    required this.label,
    required this.revenue,
    required this.sales,
    required this.change,
    required this.trendUp,
    required this.categories,
    required this.topProducts,
  });

  Color get _trendColor => trendUp ? Colors.green : Colors.red;
  IconData get _trendIcon =>
      trendUp ? Icons.arrow_upward : Icons.arrow_downward;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20.0),
            ),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Total Revenue',
                    style: TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    CurrencyFormatter.format(revenue),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 160,
                          child: _PieChart(categories: categories),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: categories.entries.map((entry) {
                            final color = _categoryColor(entry.key);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10.0),
                              child: Row(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: color,
                                      borderRadius: BorderRadius.circular(4.0),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '${entry.key} • ${entry.value}%',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20.0),
            ),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Number of Sales',
                          style: TextStyle(fontSize: 14, color: Colors.black54),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$sales',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12.0,
                      vertical: 10.0,
                    ),
                    decoration: BoxDecoration(
                      color: _trendColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                    child: Row(
                      children: [
                        Icon(_trendIcon, size: 18, color: _trendColor),
                        const SizedBox(width: 6),
                        Text(
                          '${trendUp ? '+' : '-'}$change%',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _trendColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Top Selling Products',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Column(
            children: topProducts.map((product) {
              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.0),
                ),
                elevation: 1,
                margin: const EdgeInsets.only(bottom: 12.0),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 14.0,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        child: const Icon(Icons.star, color: Colors.blue),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product['name'] as String,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${product['qty']} items sold',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${product['qty']}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'Food':
        return Colors.blue;
      case 'Drinks':
        return Colors.orange;
      case 'Supplies':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}

class _PieChart extends StatelessWidget {
  final Map<String, int> categories;

  const _PieChart({required this.categories});

  @override
  Widget build(BuildContext context) {
    final total = categories.values.fold<int>(0, (sum, value) => sum + value);
    final entries = categories.entries.toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: min(constraints.maxWidth, constraints.maxHeight),
              height: min(constraints.maxWidth, constraints.maxHeight),
              child: CustomPaint(
                painter: _PieChartPainter(entries: entries, total: total),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'Revenue mix',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                SizedBox(height: 4),
                Text(
                  'Sales',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final List<MapEntry<String, int>> entries;
  final int total;

  _PieChartPainter({required this.entries, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.2;
    final rect = Offset.zero & size;
    double startAngle = -pi / 2;

    for (final entry in entries) {
      final sweepAngle = (entry.value / total) * 2 * pi;
      paint.color = _colorForCategory(entry.key);
      canvas.drawArc(
        rect.deflate(size.width * 0.1),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;

  Color _colorForCategory(String category) {
    switch (category) {
      case 'Food':
        return Colors.blue;
      case 'Drinks':
        return Colors.orange;
      case 'Supplies':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}
