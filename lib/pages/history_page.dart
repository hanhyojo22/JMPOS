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

  String searchQuery = '';
  String selectedFilter = 'All';
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

  Widget _quickFilterChip(String label) {
    final active = activeQuickFilter == label;

    return GestureDetector(
      onTap: () {
        setState(() {
          activeQuickFilter = label;
        });
      },

      child: Container(
        margin: const EdgeInsets.only(right: 10),

        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),

        decoration: BoxDecoration(
          color: active ? const Color(0xFF667EEA) : Colors.white,

          borderRadius: BorderRadius.circular(14),

          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),

              blurRadius: 8,

              offset: const Offset(0, 3),
            ),
          ],
        ),

        child: Text(
          label,

          style: TextStyle(
            color: active ? Colors.white : Colors.black87,

            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],

      appBar: AppBar(elevation: 0, backgroundColor: Colors.transparent),

      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // TOP STATS
                // SEARCH
                // MODERN SEARCH + DATE FILTER
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),

                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Container(
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

                              child: TextField(
                                decoration: InputDecoration(
                                  hintText: 'Search transaction...',

                                  prefixIcon: const Icon(Icons.search_rounded),

                                  border: InputBorder.none,

                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),

                                onChanged: (v) {
                                  setState(() {
                                    searchQuery = v;
                                  });
                                },
                              ),
                            ),
                          ),

                          const SizedBox(width: 12),

                          GestureDetector(
                            onTap: () async {
                              final pickedDate = await showDatePicker(
                                context: context,

                                initialDate: DateTime.now(),

                                firstDate: DateTime(2020),

                                lastDate: DateTime(2100),
                              );

                              if (pickedDate != null) {
                                final months = [
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

                                final selectedDate =
                                    '${months[pickedDate.month - 1]} ${pickedDate.day}, ${pickedDate.year}';

                                setState(() {
                                  searchQuery = selectedDate;
                                });
                              }
                            },

                            child: Container(
                              width: 58,
                              height: 58,

                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF667EEA),
                                    Color(0xFF764BA2),
                                  ],
                                ),

                                borderRadius: BorderRadius.circular(18),

                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF667EEA,
                                    ).withValues(alpha: 0.25),

                                    blurRadius: 12,

                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),

                              child: const Icon(
                                Icons.calendar_month_rounded,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      // QUICK DATE FILTERS
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,

                        child: Row(
                          children: [
                            _quickFilterChip('Today'),

                            _quickFilterChip('Yesterday'),

                            _quickFilterChip('This Week'),

                            _quickFilterChip('This Month'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),

                  child: Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          label: 'Orders',
                          value: '${salesHistory.length}',
                        ),
                      ),

                      const SizedBox(width: 12),

                      Expanded(
                        child: _StatCard(
                          label: 'Revenue',
                          value: CurrencyFormatter.format(totalSales),
                        ),
                      ),
                    ],
                  ),
                ),

                // HISTORY LIST
                Expanded(
                  child: salesHistory.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,

                            children: [
                              Icon(
                                Icons.receipt_long_outlined,
                                size: 70,
                                color: Colors.grey[300],
                              ),

                              const SizedBox(height: 12),

                              Text(
                                'No transaction history',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),

                          itemCount: filteredHistory.length,

                          itemBuilder: (context, index) {
                            final sale = filteredHistory[index];

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),

                              padding: const EdgeInsets.all(16),

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

                              child: Row(
                                children: [
                                  Container(
                                    width: 52,

                                    height: 52,

                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF667EEA,
                                      ).withValues(alpha: 0.1),

                                      borderRadius: BorderRadius.circular(14),
                                    ),

                                    child: const Icon(
                                      Icons.receipt_long_rounded,

                                      color: Color(0xFF667EEA),
                                    ),
                                  ),

                                  const SizedBox(width: 14),

                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,

                                      children: [
                                        Text(
                                          sale['product'],

                                          maxLines: 1,

                                          overflow: TextOverflow.ellipsis,

                                          style: const TextStyle(
                                            fontSize: 15,

                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),

                                        const SizedBox(height: 4),

                                        Text(
                                          '${sale['date']} • ${sale['time']}',

                                          style: TextStyle(
                                            fontSize: 12,

                                            color: Colors.grey[500],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,

                                    children: [
                                      Text(
                                        CurrencyFormatter.format(
                                          (sale['total'] as num).toDouble(),
                                        ),

                                        style: const TextStyle(
                                          fontSize: 15,

                                          fontWeight: FontWeight.bold,

                                          color: Color(0xFF667EEA),
                                        ),
                                      ),

                                      const SizedBox(height: 4),

                                      Text(
                                        'Qty ${sale['quantity']}',

                                        style: TextStyle(
                                          fontSize: 12,

                                          color: Colors.grey[500],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _filterChip(String label) {
    final active = selectedFilter == label;

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedFilter = label;
        });
      },

      child: Container(
        margin: const EdgeInsets.only(right: 10),

        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),

        decoration: BoxDecoration(
          color: active ? const Color(0xFF667EEA) : Colors.white,

          borderRadius: BorderRadius.circular(14),
        ),

        child: Text(
          label,

          style: TextStyle(
            color: active ? Colors.white : Colors.black87,

            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),

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

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])),

          const SizedBox(height: 8),

          Text(
            value,

            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
