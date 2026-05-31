import 'package:flutter/material.dart';
import 'package:pos_app/database/database_helper.dart';
import 'package:pos_app/utils/currency.dart';
import 'recent_sales.dart';

class HistoryPage extends StatefulWidget {
  final String currentUsername;

  const HistoryPage({super.key, required this.currentUsername});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> salesHistory = [];
  bool loading = true;

  // ── Palette ────────────────────────────────────────────────────
  static const Color _purple = Color(0xFF6E62C4); // primary

  static const Color _purpleLight = Color(0xFFEFEDF9); // tint bg

  // voided uses a warm rose that contrasts the purple
  static const Color _red = Color(0xFFD32F2F);
  static const Color _redLight = Color(0xFFFFEBEE);
  // neutral
  static const Color _textDark = Color(0xFF212121);
  static const Color _textGrey = Color(0xFF757575);
  static const Color _divider = Color(0xFFEEEEEE);
  static const Color _bg = Color(0xFFF5F4FC); // very light purple tint

  String _selectedTab = 'Completed'; // 'Completed' | 'Void'
  String _selectedSort = 'Newest';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  // ── Computed ───────────────────────────────────────────────────
  List<Map<String, dynamic>> get _completedSales =>
      salesHistory.where((s) => s['isVoided'] != true).toList();

  List<Map<String, dynamic>> get _voidedSales =>
      salesHistory.where((s) => s['isVoided'] == true).toList();

  // ── Lifecycle ──────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    loadSalesHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────
  Future<void> loadSalesHistory() async {
    setState(() => loading = true);
    _fadeCtrl.reset();

    final db = await DatabaseHelper.instance.database;
    await DatabaseHelper.instance.ensureSalesSchema();
    await DatabaseHelper.instance.completeDueSales();

    final history = await db.rawQuery('''
      SELECT
        MIN(sales.id) AS id,
        COALESCE(NULLIF(sales.receipt_number,''),'INV-'||printf('%06d',MIN(sales.id))) AS receipt_number,
        GROUP_CONCAT(sales.product_name,', ') AS product_name,
        SUM(sales.quantity)   AS quantity,
        SUM(sales.total)      AS total,
        MIN(sales.created_at) AS created_at,
        MAX(sales.voided_at)  AS voided_at,
        COALESCE(MAX(sales.void_reason),'') AS void_reason
      FROM sales
      LEFT JOIN products ON products.id = sales.product_id
      GROUP BY COALESCE(NULLIF(sales.receipt_number,''),substr(sales.created_at,1,19))
      ORDER BY MAX(sales.created_at) DESC, MAX(sales.id) DESC
    ''');

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

    setState(() {
      salesHistory = history.map((sale) {
        DateTime? createdAt;
        try {
          createdAt = DateTime.parse(sale['created_at'].toString()).toLocal();
        } catch (_) {}

        String dateStr = '';
        String timeStr = '';
        if (createdAt != null) {
          dateStr =
              '${months[createdAt.month - 1]} ${createdAt.day.toString().padLeft(2, '0')}, ${createdAt.year}';
          final h = createdAt.hour % 12 == 0 ? 12 : createdAt.hour % 12;
          final m = createdAt.minute.toString().padLeft(2, '0');
          final period = createdAt.hour >= 12 ? 'PM' : 'AM';
          timeStr = '$h:$m $period';
        }

        return {
          'id': sale['id'],
          'receiptNumber': sale['receipt_number']?.toString() ?? '',
          'product': sale['product_name'] ?? '',
          'date': dateStr,
          'time': timeStr,
          'createdAt': createdAt,
          'quantity': sale['quantity'],
          'total': sale['total'],
          'isVoided': (sale['voided_at']?.toString() ?? '').isNotEmpty,
          'voidReason': sale['void_reason']?.toString() ?? '',
        };
      }).toList();
      loading = false;
    });

    _fadeCtrl.forward();
  }

  // ── Sort ───────────────────────────────────────────────────────
  void _showSortSheet() {
    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SortSheet(
        current: _selectedSort,
        onSelect: (sort) => setState(() => _selectedSort = sort),
      ),
    );
  }

  List<Map<String, dynamic>> _sorted(List<Map<String, dynamic>> items) {
    final query = _searchQuery.trim().toLowerCase();
    final list = items.where((sale) {
      if (query.isEmpty) return true;
      final total = (sale['total'] as num?)?.toDouble() ?? 0;
      final isVoided = sale['isVoided'] == true;
      return [
        sale['receiptNumber'],
        sale['product'],
        sale['date'],
        sale['time'],
        sale['quantity'],
        total,
        CurrencyFormatter.format(total),
        isVoided ? 'void voided' : 'complete completed',
        sale['voidReason'],
      ].any((value) => (value?.toString() ?? '').toLowerCase().contains(query));
    }).toList();
    switch (_selectedSort) {
      case 'Oldest':
        list.sort((a, b) => _cmpDate(b, a));
        break;
      case 'Highest Amount':
        list.sort((a, b) => (b['total'] as num).compareTo(a['total'] as num));
        break;
      case 'Lowest Amount':
        list.sort((a, b) => (a['total'] as num).compareTo(b['total'] as num));
        break;
      default:
        list.sort(_cmpDate);
    }
    return list;
  }

  int _cmpDate(Map<String, dynamic> a, Map<String, dynamic> b) {
    final aD = a['createdAt'] as DateTime?;
    final bD = b['createdAt'] as DateTime?;
    if (aD != null && bD != null) return bD.compareTo(aD);
    if (aD != null) return -1;
    if (bD != null) return 1;
    return ((b['id'] as num?)?.toInt() ?? 0).compareTo(
      (a['id'] as num?)?.toInt() ?? 0,
    );
  }

  // ══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchBar(),
            _buildTabs(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  // ── App bar ────────────────────────────────────────────────────
  // ── Tabs ───────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (query) => setState(() => _searchQuery = query),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search sales',
          prefixIcon: const Icon(Icons.search_rounded, color: _textGrey),
          suffixIconConstraints: const BoxConstraints(minWidth: 48),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_searchQuery.isNotEmpty)
                IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(
                    Icons.close_rounded,
                    color: _textGrey,
                    size: 20,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
              IconButton(
                tooltip: 'Sort sales',
                icon: const Icon(
                  Icons.filter_alt_outlined,
                  color: _textGrey,
                  size: 22,
                ),
                onPressed: _showSortSheet,
              ),
            ],
          ),
          filled: true,
          fillColor: _bg,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _TabItem(
            label: 'Completed Sales',
            selected: _selectedTab == 'Completed',
            activeColor: _purple,
            alignment: Alignment.centerLeft,
            onTap: () => setState(() => _selectedTab = 'Completed'),
          ),
          _TabItem(
            label: 'Void Sales',
            selected: _selectedTab == 'Void',
            activeColor: _red,
            alignment: Alignment.centerRight,
            onTap: () => setState(() => _selectedTab = 'Void'),
          ),
        ],
      ),
    );
  }

  // ── Summary cards ──────────────────────────────────────────────

  // ── Body ───────────────────────────────────────────────────────
  Widget _buildBody() {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: _purple));
    }

    final isCompleted = _selectedTab == 'Completed';
    final items = _sorted(isCompleted ? _completedSales : _voidedSales);

    return FadeTransition(
      opacity: _fadeAnim,
      child: RefreshIndicator(
        color: _purple,
        onRefresh: loadSalesHistory,
        child: CustomScrollView(
          slivers: [
            if (items.isEmpty)
              SliverFillRemaining(
                child: _buildEmpty(
                  isCompleted,
                  hasSearchQuery: _searchQuery.trim().isNotEmpty,
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate((_, i) {
                  final sale = items[i];
                  final isLast = i == items.length - 1;
                  return _buildRow(sale, isLast);
                }, childCount: items.length),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  // ── Section header ─────────────────────────────────────────────

  // ── Transaction row ────────────────────────────────────────────
  Widget _buildRow(Map<String, dynamic> sale, bool isLast) {
    final total = (sale['total'] as num?)?.toDouble() ?? 0.0;
    final saleId = (sale['id'] as num?)?.toInt();
    final receipt = sale['receiptNumber']?.toString().trim() ?? '';
    final isVoided = sale['isVoided'] == true;
    final accentColor = isVoided ? _red : _purple;

    return InkWell(
      onTap: () async {
        if (saleId == null) return;
        final changed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => RecentSalesPage(
              saleId: saleId,
              currentUsername: widget.currentUsername,
            ),
          ),
        );
        if (changed == true && mounted) await loadSalesHistory();
      },
      child: Container(
        color: Colors.white,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Invoice + date/time
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          receipt,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: _textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${sale['date'] ?? ''}  ${sale['time'] ?? ''}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: _textGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Amount + badge
                  SizedBox(
                    width: 104,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          CurrencyFormatter.format(total),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: accentColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerRight,
                          child: !isVoided
                              ? _StatusBadge(
                                  label: 'Completed',
                                  color: _purple,
                                  bg: _purpleLight,
                                )
                              : _StatusBadge(
                                  label: 'Voided',
                                  color: _red,
                                  bg: _redLight,
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: Color(0xFFBDBDBD),
                  ),
                ],
              ),
            ),
            if (!isLast)
              const Divider(
                height: 1,
                thickness: 1,
                color: _divider,
                indent: 16,
                endIndent: 16,
              ),
          ],
        ),
      ),
    );
  }

  // ── Empty ─────────────────────────────────────────────────────
  Widget _buildEmpty(bool isCompleted, {bool hasSearchQuery = false}) {
    final color = isCompleted ? _purple : _red;
    final bg = isCompleted ? _purpleLight : _redLight;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(
              isCompleted ? Icons.receipt_long_outlined : Icons.cancel_outlined,
              color: color.withValues(alpha: 0.6),
              size: 32,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            hasSearchQuery
                ? 'No matching sales'
                : isCompleted
                ? 'No completed sales'
                : 'No void sales',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasSearchQuery
                ? 'Try a different receipt, product, date, or amount'
                : isCompleted
                ? 'Completed transactions will appear here'
                : 'Voided transactions will appear here',
            style: const TextStyle(fontSize: 13, color: _textGrey),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Reusable widgets
// ═══════════════════════════════════════════════════════════════

class _TabItem extends StatelessWidget {
  final String label;
  final bool selected;
  final Color activeColor;
  final Alignment alignment;
  final VoidCallback onTap;

  const _TabItem({
    required this.label,
    required this.selected,
    required this.activeColor,
    required this.alignment,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(
                color: selected ? activeColor : const Color(0xFFE0E0E0),
                width: selected ? 2.5 : 1,
              ),
            ),
          ),
          child: Align(
            alignment: alignment,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: selected ? activeColor : const Color(0xFF9E9E9E),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;

  const _StatusBadge({
    required this.label,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Sort bottom sheet
// ═══════════════════════════════════════════════════════════════

class _SortSheet extends StatefulWidget {
  final String current;
  final void Function(String) onSelect;

  const _SortSheet({required this.current, required this.onSelect});

  @override
  State<_SortSheet> createState() => _SortSheetState();
}

class _SortSheetState extends State<_SortSheet> {
  static const Color _purple = Color(0xFF6E62C4);
  late String _selected;

  final _options = [
    {'key': 'Newest', 'label': 'Newest First', 'icon': Icons.schedule_rounded},
    {'key': 'Oldest', 'label': 'Oldest First', 'icon': Icons.history_rounded},
    {
      'key': 'Highest Amount',
      'label': 'Highest Amount',
      'icon': Icons.trending_up_rounded,
    },
    {
      'key': 'Lowest Amount',
      'label': 'Lowest Amount',
      'icon': Icons.trending_down_rounded,
    },
  ];

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Sort By',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF212121),
                ),
              ),
            ),
            const SizedBox(height: 14),
            ..._options.map((opt) {
              final sel = _selected == opt['key'];
              return GestureDetector(
                onTap: () => setState(() => _selected = opt['key'] as String),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: sel
                        ? const Color(0xFFE8F5E9)
                        : const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: sel ? _purple : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        opt['icon'] as IconData,
                        color: sel ? _purple : const Color(0xFF9E9E9E),
                        size: 18,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          opt['label'] as String,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: sel ? _purple : const Color(0xFF424242),
                          ),
                        ),
                      ),
                      if (sel)
                        Container(
                          width: 18,
                          height: 18,
                          decoration: const BoxDecoration(
                            color: _purple,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                widget.onSelect(_selected);
                Navigator.pop(context);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _purple,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Text(
                    'Apply',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
