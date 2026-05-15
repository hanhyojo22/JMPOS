import 'package:flutter/material.dart';
import 'package:pos_app/database/database_helper.dart';
import 'package:pos_app/utils/currency.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>> salesHistory = [];
  bool loading = true;
  static const Color _primary = Color(0xFF5C6BC0);
  static const Color _surface = Color(0xFFF4F5FF);
  static const Color _textPrimary = Color(0xFF1A1F36);
  static const Color _textSecondary = Color(0xFF6B7280);
  static const Color _success = Color(0xFF10B981);
  String searchQuery = '';
  String selectedFilter = 'All';
  double get historySalesTotal => salesHistory.fold(
    0.0,
    (s, h) => s + ((h['total'] as num?)?.toDouble() ?? 0.0),
  );
  @override
  void initState() {
    super.initState();
    loadSalesHistory();
  }

  Future<void> loadSalesHistory() async {
    final db = await DatabaseHelper.instance.database;

    final history = await db.query('sales', orderBy: 'id DESC');

    setState(() {
      salesHistory = history.map((sale) {
        DateTime? createdAt;

        try {
          createdAt = DateTime.parse(sale['created_at'].toString()).toLocal();
        } catch (_) {}

        const months = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];

        final dateStr = createdAt != null
            ? '${months[createdAt.month - 1]} ${createdAt.day}, ${createdAt.year}'
            : '';

        final h = createdAt != null
            ? (createdAt.hour % 12 == 0 ? 12 : createdAt.hour % 12)
            : 0;

        final m = createdAt?.minute.toString().padLeft(2, '0') ?? '00';

        final period = (createdAt?.hour ?? 0) >= 12 ? 'PM' : 'AM';

        final timeStr = createdAt != null ? '$h:$m $period' : '';

        return {
          'product': sale['product_name'] ?? '',
          'date': dateStr,
          'time': timeStr,
          'quantity': sale['quantity'],
          'total': sale['total'],
        };
      }).toList();

      loading = false;
    });
  }

  String activeQuickFilter = '';

  double get totalSales => salesHistory.fold(
    0.0,
    (sum, item) => sum + ((item['total'] as num?)?.toDouble() ?? 0.0),
  );
  List<Map<String, dynamic>> get filteredHistory {
    List<Map<String, dynamic>> items = List.from(salesHistory);

    // SEARCH
    if (searchQuery.isNotEmpty) {
      items = items.where((sale) {
        return sale['product'].toString().toLowerCase().contains(
          searchQuery.toLowerCase(),
        );
      }).toList();
    }

    final now = DateTime.now();

    // DATE FILTER
    if (selectedFilter == 'Today') {
      items = items.where((sale) {
        final date = sale['date'].toString().toLowerCase();

        return date.contains('${now.day}');
      }).toList();
    }

    return items;
  }

  @override
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,

      body: SafeArea(
        child: Column(
          children: [
            // SEARCH
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),

                child: TextField(
                  onChanged: (v) {
                    setState(() {
                      searchQuery = v;
                    });
                  },

                  decoration: InputDecoration(
                    hintText: 'Search transaction...',
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: _textSecondary.withValues(alpha: 0.5),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),

            // STATS
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  _HistoryStat(
                    label: 'Total Revenue',
                    value: CurrencyFormatter.format(historySalesTotal),
                    icon: Icons.account_balance_wallet_outlined,
                    color: _success,
                  ),

                  const SizedBox(width: 12),

                  _HistoryStat(
                    label: 'Transactions',
                    value: '${salesHistory.length}',
                    icon: Icons.receipt_long_outlined,
                    color: _primary,
                  ),
                ],
              ),
            ),
            // HEADER
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(
                children: [
                  const Text(
                    'Recent Sales',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                  ),

                  const Spacer(),

                  Text(
                    '${filteredHistory.length} records',
                    style: const TextStyle(fontSize: 13, color: _textSecondary),
                  ),
                ],
              ),
            ),

            Expanded(
              child: loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _primary),
                    )
                  : filteredHistory.isEmpty
                  ? _buildEmptyHistory()
                  : RefreshIndicator(
                      color: _primary,
                      onRefresh: loadSalesHistory,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: filteredHistory.length,
                        itemBuilder: (_, i) =>
                            _buildHistoryCard(filteredHistory[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> sale) {
    final total = (sale['total'] as num?)?.toDouble() ?? 0.0;
    final qty = sale['quantity'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),

      child: Padding(
        padding: const EdgeInsets.all(14),

        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,

              decoration: BoxDecoration(
                color: _success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(13),
              ),

              child: const Icon(
                Icons.receipt_rounded,
                color: _success,
                size: 22,
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sale['product'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,

                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                  ),

                  const SizedBox(height: 3),

                  Text(
                    '${sale['date']}  •  ${sale['time']}',

                    style: const TextStyle(fontSize: 12, color: _textSecondary),
                  ),
                ],
              ),
            ),

            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  CurrencyFormatter.format(total),

                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary,
                  ),
                ),

                const SizedBox(height: 4),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),

                  decoration: BoxDecoration(
                    color: _success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),

                  child: Text(
                    'x$qty sold',

                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _success,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyHistory() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,

            decoration: BoxDecoration(
              color: _primary.withValues(alpha: 0.07),
              shape: BoxShape.circle,
            ),

            child: Icon(
              Icons.receipt_long_outlined,
              color: _primary.withValues(alpha: 0.45),
              size: 38,
            ),
          ),

          const SizedBox(height: 14),

          const Text(
            'No sales yet',

            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),

          const SizedBox(height: 4),

          const Text(
            'Completed sales will appear here',

            style: TextStyle(fontSize: 13, color: _textSecondary),
          ),
        ],
      ),
    );
  }
}

class _HistoryStat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;

  const _HistoryStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),

        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),

          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),

        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),

              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),

              child: Icon(icon, color: color, size: 18),
            ),

            const SizedBox(width: 10),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,

                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),

                  Text(
                    label,

                    style: const TextStyle(
                      fontSize: 11,
                      color: _HistoryPageState._textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
