import 'package:flutter/material.dart';
import 'package:pos_app/database/database_helper.dart';
import 'package:pos_app/utils/currency.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> salesHistory = [];
  bool loading = true;
  static const Color _primary = Color(0xFF5C6BC0);
  static const Color _surface = Color(0xFFF4F5FF);
  static const Color _textPrimary = Color(0xFF1A1F36);
  static const Color _textSecondary = Color(0xFF6B7280);
  static const Color _success = Color(0xFF10B981);
  String searchQuery = '';
  String _selectedSort = 'Newest';
  String selectedFilter = 'All';
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _pageSurface => _isDark ? const Color(0xFF0F172A) : _surface;
  Color get _panelSurface => _isDark ? const Color(0xFF111827) : Colors.white;
  Color get _primaryText => _isDark ? const Color(0xFFF8FAFC) : _textPrimary;
  Color get _secondaryText =>
      _isDark ? const Color(0xFFCBD5E1) : _textSecondary;
  Color get _softShadow => _isDark
      ? Colors.black.withValues(alpha: 0.22)
      : Colors.black.withValues(alpha: 0.04);
  double get historySalesTotal => salesHistory.fold(
    0.0,
    (s, h) => s + ((h['total'] as num?)?.toDouble() ?? 0.0),
  );
  @override
  void initState() {
    super.initState();
    loadSalesHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showSortSheet() {
    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _HistorySortSheet(
        current: _selectedSort,
        onSelect: (s) {
          setState(() {
            _selectedSort = s;
          });
        },
      ),
    );
  }

  Future<void> loadSalesHistory() async {
    final db = await DatabaseHelper.instance.database;

    final history = await db.query(
      'sales',
      orderBy: 'created_at DESC, id DESC',
    );

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
          'id': sale['id'],
          'product': sale['product_name'] ?? '',
          'date': dateStr,
          'time': timeStr,
          'createdAt': createdAt,
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

    // SORT
    switch (_selectedSort) {
      case 'Newest':
        items.sort(_compareNewestFirst);
        break;

      case 'Oldest':
        items.sort((a, b) => _compareNewestFirst(b, a));
        break;

      case 'Highest Amount':
        items.sort((a, b) => (b['total'] as num).compareTo(a['total'] as num));
        break;

      case 'Lowest Amount':
        items.sort((a, b) => (a['total'] as num).compareTo(b['total'] as num));
        break;

      case 'Most Quantity':
        items.sort(
          (a, b) => (b['quantity'] as int).compareTo(a['quantity'] as int),
        );
        break;
    }

    return items;
  }

  int _compareNewestFirst(Map<String, dynamic> a, Map<String, dynamic> b) {
    final aCreatedAt = a['createdAt'] as DateTime?;
    final bCreatedAt = b['createdAt'] as DateTime?;

    if (aCreatedAt != null && bCreatedAt != null) {
      final dateCompare = bCreatedAt.compareTo(aCreatedAt);
      if (dateCompare != 0) return dateCompare;
    } else if (aCreatedAt != null) {
      return -1;
    } else if (bCreatedAt != null) {
      return 1;
    }

    final aId = (a['id'] as num?)?.toInt() ?? 0;
    final bId = (b['id'] as num?)?.toInt() ?? 0;
    return bId.compareTo(aId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageSurface,

      body: SafeArea(
        child: Column(
          children: [
            // SEARCH
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: _panelSurface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: _softShadow,
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) {
                    setState(() {
                      searchQuery = v;
                    });
                  },
                  style: TextStyle(
                    fontSize: 15,
                    color: _primaryText,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search transaction...',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: _secondaryText.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w400,
                    ),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 14, right: 10),
                      child: Icon(
                        Icons.search_rounded,
                        color: _secondaryText.withValues(alpha: 0.75),
                        size: 22,
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 0,
                      minHeight: 0,
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (searchQuery.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              setState(() {
                                searchQuery = '';
                              });
                            },
                            child: Container(
                              margin: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _secondaryText.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.close_rounded,
                                size: 16,
                                color: _secondaryText,
                              ),
                            ),
                          ),
                        Container(
                          width: 1,
                          height: 24,
                          margin: const EdgeInsets.only(right: 4),
                          color: _secondaryText.withValues(alpha: 0.18),
                        ),
                        Tooltip(
                          message: 'Sort history',
                          child: GestureDetector(
                            onTap: _showSortSheet,
                            child: Container(
                              width: 42,
                              height: 42,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: _selectedSort != 'Newest'
                                    ? _primary.withValues(alpha: 0.1)
                                    : Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.tune_rounded,
                                color: _selectedSort != 'Newest'
                                    ? _primary
                                    : _secondaryText,
                                size: 21,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 0,
                      minHeight: 0,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
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
                  Text(
                    'Recent Sales',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _primaryText,
                    ),
                  ),

                  const Spacer(),

                  Text(
                    '${filteredHistory.length} records',
                    style: TextStyle(fontSize: 13, color: _secondaryText),
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
        color: _panelSurface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _softShadow,
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

                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _primaryText,
                    ),
                  ),

                  const SizedBox(height: 3),

                  Text(
                    '${sale['date']}  •  ${sale['time']}',

                    style: TextStyle(fontSize: 12, color: _secondaryText),
                  ),
                ],
              ),
            ),

            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  CurrencyFormatter.format(total),

                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _primaryText,
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

          Text(
            'No sales yet',

            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _primaryText,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            'Completed sales will appear here',

            style: TextStyle(fontSize: 13, color: _secondaryText),
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

class _HistorySortSheet extends StatefulWidget {
  final String current;
  final void Function(String) onSelect;

  const _HistorySortSheet({required this.current, required this.onSelect});

  @override
  State<_HistorySortSheet> createState() => _HistorySortSheetState();
}

class _HistorySortSheetState extends State<_HistorySortSheet> {
  static const Color _primary = Color(0xFF5C6BC0);
  static const Color _textPrimary = Color(0xFF1A1F36);
  static const Color _textSecondary = Color(0xFF6B7280);

  late String _selected;

  final _options = [
    {
      'key': 'Newest',
      'label': 'Newest First',
      'sub': 'Latest transactions first',
      'icon': Icons.schedule_rounded,
    },
    {
      'key': 'Oldest',
      'label': 'Oldest First',
      'sub': 'Earliest transactions first',
      'icon': Icons.history_rounded,
    },
    {
      'key': 'Highest Amount',
      'label': 'Highest Amount',
      'sub': 'Largest sales first',
      'icon': Icons.arrow_downward_rounded,
    },
    {
      'key': 'Lowest Amount',
      'label': 'Lowest Amount',
      'sub': 'Smallest sales first',
      'icon': Icons.arrow_upward_rounded,
    },
    {
      'key': 'Most Quantity',
      'label': 'Most Quantity',
      'sub': 'Most items sold first',
      'icon': Icons.layers_rounded,
    },
  ];

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(24, 0, 24, 60),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 22),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Sort History',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _options.length,
                  itemBuilder: (context, index) {
                    final opt = _options[index];
                    final selected = _selected == opt['key'];

                    return GestureDetector(
                      onTap: () =>
                          setState(() => _selected = opt['key'] as String),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: selected
                              ? _primary.withValues(alpha: 0.06)
                              : Colors.grey[50],
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected ? _primary : Colors.grey[200]!,
                            width: selected ? 1.8 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: selected
                                    ? _primary.withValues(alpha: 0.1)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                opt['icon'] as IconData,
                                color: selected ? _primary : _textSecondary,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    opt['label'] as String,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: selected ? _primary : _textPrimary,
                                    ),
                                  ),
                                  Text(
                                    opt['sub'] as String,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: _textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (selected)
                              Container(
                                width: 20,
                                height: 20,
                                decoration: const BoxDecoration(
                                  color: _primary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 13,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () {
                  widget.onSelect(_selected);
                  Navigator.pop(context);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_primary, Color(0xFF7C4DFF)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Text(
                      'Apply',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
