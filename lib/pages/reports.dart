import 'dart:math';
import 'package:flutter/material.dart';
import 'package:pos_app/database/database_helper.dart';
import 'package:pos_app/utils/currency.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Data per period
  final Map<String, _ReportData> _data = {
    'Today': _ReportData(),
    'Weekly': _ReportData(),
    'Monthly': _ReportData(),
  };

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadReports();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadReports() async {
    setState(() => _loading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query('sales', orderBy: 'created_at DESC');

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));
      final monthStart = DateTime(now.year, now.month, 1);

      for (final period in ['Today', 'Weekly', 'Monthly']) {
        double revenue = 0;
        int orders = 0;
        final Map<String, double> productRevenue = {};
        final Map<String, int> productQty = {};
        final Map<String, double> categoryRevenue = {};

        for (final row in rows) {
          DateTime? dt;
          try {
            dt = DateTime.parse(row['created_at'].toString()).toLocal();
          } catch (_) {
            continue;
          }

          bool inRange = false;
          if (period == 'Today') inRange = !dt.isBefore(todayStart);
          if (period == 'Weekly') inRange = !dt.isBefore(weekStart);
          if (period == 'Monthly') inRange = !dt.isBefore(monthStart);
          if (!inRange) continue;

          final double total = (row['total'] as num?)?.toDouble() ?? 0;
          final int qty = (row['quantity'] as num?)?.toInt() ?? 0;
          final String name = row['product_name'] as String? ?? 'Unknown';

          // Get category from products table
          final productRows = await db.query(
            'products',
            columns: ['category'],
            where: 'id = ?',
            whereArgs: [row['product_id']],
          );
          final String category = productRows.isNotEmpty
              ? (productRows.first['category'] as String? ?? 'Other')
              : 'Other';

          revenue += total;
          orders += 1;
          productRevenue[name] = (productRevenue[name] ?? 0) + total;
          productQty[name] = (productQty[name] ?? 0) + qty;
          categoryRevenue[category] = (categoryRevenue[category] ?? 0) + total;
        }

        // Top 5 products by qty
        final sortedProducts = productQty.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final topProducts = sortedProducts.take(5).toList();

        // Category percentages
        final Map<String, int> categoryPct = {};
        if (revenue > 0) {
          categoryRevenue.forEach((cat, rev) {
            categoryPct[cat] = ((rev / revenue) * 100).round();
          });
        }

        _data[period] = _ReportData(
          revenue: revenue,
          orders: orders,
          topProducts: topProducts,
          categoryPct: categoryPct,
        );
      }
    } catch (e) {
      debugPrint('Report error: $e');
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reports',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Sales performance overview',
                        style: TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: _loadReports,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Tab bar ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.black54,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicatorPadding: const EdgeInsets.symmetric(horizontal: 4),
                  labelPadding: const EdgeInsets.symmetric(vertical: 12),
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: 'Today'),
                    Tab(text: 'Weekly'),
                    Tab(text: 'Monthly'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Content ──────────────────────────────────────────────
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: ['Today', 'Weekly', 'Monthly'].map((period) {
                        final d = _data[period]!;
                        return _ReportView(period: period, data: d);
                      }).toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Data model ───────────────────────────────────────────────────────────────
class _ReportData {
  final double revenue;
  final int orders;
  final List<MapEntry<String, int>> topProducts;
  final Map<String, int> categoryPct;

  _ReportData({
    this.revenue = 0,
    this.orders = 0,
    this.topProducts = const [],
    this.categoryPct = const {},
  });
}

// ─── Report view ──────────────────────────────────────────────────────────────
class _ReportView extends StatelessWidget {
  final String period;
  final _ReportData data;

  const _ReportView({required this.period, required this.data});

  double get _avgOrder => data.orders > 0 ? data.revenue / data.orders : 0;

  @override
  Widget build(BuildContext context) {
    final bool empty = data.revenue == 0 && data.orders == 0;

    if (empty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.bar_chart_outlined,
                size: 40,
                color: Color(0xFF667EEA),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No sales data for $period',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Complete a sale to see reports here',
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {},
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Revenue hero card ──────────────────────────────────
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF667EEA).withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.trending_up_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '$period Revenue',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    CurrencyFormatter.format(data.revenue),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _HeroStat(
                          label: 'Orders',
                          value: '${data.orders}',
                          icon: Icons.receipt_long_outlined,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                      Expanded(
                        child: _HeroStat(
                          label: 'Avg. Order',
                          value: CurrencyFormatter.format(_avgOrder),
                          icon: Icons.calculate_outlined,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Category breakdown ─────────────────────────────────
            if (data.categoryPct.isNotEmpty) ...[
              _SectionHeader(
                title: 'Category Breakdown',
                icon: Icons.pie_chart_outline_rounded,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: _cardDecoration(),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 130,
                      height: 130,
                      child: _DonutChart(categories: data.categoryPct),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: data.categoryPct.entries.map((e) {
                          final color = _categoryColor(e.key);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    e.key,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${e.value}%',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: color,
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
              ),
              const SizedBox(height: 20),
            ],

            // ── Category bar chart ─────────────────────────────────
            if (data.categoryPct.isNotEmpty) ...[
              _SectionHeader(
                title: 'Sales by Category',
                icon: Icons.bar_chart_rounded,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: _cardDecoration(),
                child: Column(
                  children: data.categoryPct.entries.map((e) {
                    final color = _categoryColor(e.key);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                e.key,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${e.value}%',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: e.value / 100,
                              backgroundColor: color.withValues(alpha: 0.1),
                              valueColor: AlwaysStoppedAnimation<Color>(color),
                              minHeight: 10,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ── Top products ───────────────────────────────────────
            if (data.topProducts.isNotEmpty) ...[
              _SectionHeader(
                title: 'Top Selling Products',
                icon: Icons.emoji_events_outlined,
              ),
              const SizedBox(height: 12),
              Container(
                decoration: _cardDecoration(),
                child: Column(
                  children: data.topProducts.asMap().entries.map((e) {
                    final rank = e.key + 1;
                    final product = e.value;
                    final isLast = rank == data.topProducts.length;
                    final rankColors = [
                      const Color(0xFFFFD700),
                      const Color(0xFFC0C0C0),
                      const Color(0xFFCD7F32),
                    ];
                    final rankColor = rank <= 3
                        ? rankColors[rank - 1]
                        : Colors.grey[300]!;

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              // Rank badge
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: rankColor.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: rank <= 3
                                      ? Icon(
                                          Icons.emoji_events_rounded,
                                          size: 18,
                                          color: rankColor,
                                        )
                                      : Text(
                                          '$rank',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey[600],
                                            fontSize: 13,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      product.key,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${product.value} units sold',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Mini bar
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF667EEA,
                                      ).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${product.value}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Color(0xFF667EEA),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (!isLast)
                          Divider(
                            height: 1,
                            indent: 64,
                            endIndent: 16,
                            color: Colors.grey[100],
                          ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.05),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );

  Color _categoryColor(String cat) {
    final Map<String, Color> colors = {
      'Beverages': const Color(0xFF667EEA),
      'Groceries': const Color(0xFF43B89C),
      'Snacks': const Color(0xFFF59E0B),
      'Household': const Color(0xFF8B5CF6),
      'Food': const Color(0xFF667EEA),
      'Drinks': const Color(0xFFF59E0B),
      'Supplies': const Color(0xFF43B89C),
      'Other': Colors.grey,
    };
    return colors[cat] ?? Colors.grey;
  }
}

// ─── Hero stat ────────────────────────────────────────────────────────────────
class _HeroStat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _HeroStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.7), size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 11,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF667EEA)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

// ─── Donut chart ──────────────────────────────────────────────────────────────
class _DonutChart extends StatelessWidget {
  final Map<String, int> categories;
  const _DonutChart({required this.categories});

  @override
  Widget build(BuildContext context) {
    final total = categories.values.fold<int>(0, (s, v) => s + v);
    return CustomPaint(
      painter: _DonutPainter(categories: categories, total: total),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$total%',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              'Total',
              style: TextStyle(fontSize: 10, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final Map<String, int> categories;
  final int total;

  _DonutPainter({required this.categories, required this.total});

  static const Map<String, Color> _colors = {
    'Beverages': Color(0xFF667EEA),
    'Groceries': Color(0xFF43B89C),
    'Snacks': Color(0xFFF59E0B),
    'Household': Color(0xFF8B5CF6),
    'Food': Color(0xFF667EEA),
    'Drinks': Color(0xFFF59E0B),
    'Supplies': Color(0xFF43B89C),
    'Other': Colors.grey,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;
    final strokeWidth = radius * 0.32;
    final rect = Rect.fromCircle(
      center: center,
      radius: radius - strokeWidth / 2,
    );
    double start = -pi / 2;
    const gap = 0.04;

    for (final entry in categories.entries) {
      final sweep = (entry.value / total) * 2 * pi - gap;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = _colors[entry.key] ?? Colors.grey;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += (entry.value / total) * 2 * pi;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}
