import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_app/utils/currency.dart';
import 'package:pos_app/database/database_helper.dart';
import 'package:pos_app/pages/edit_product_page.dart';

class ProductsPage extends StatefulWidget {
  final String? scannedBarcode;
  final Function(Map<String, dynamic>)? onEditProduct;
  const ProductsPage({super.key, this.scannedBarcode, this.onEditProduct});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage>
    with TickerProviderStateMixin {
  // ── Design tokens ──────────────────────────────────────────────────────────
  static const Color _primary = Color(0xFF5C6BC0);
  static const Color _primaryDark = Color(0xFF3949AB);
  static const Color _surface = Color(0xFFF4F5FF);
  static const Color _textPrimary = Color(0xFF1A1F36);
  static const Color _textSecondary = Color(0xFF6B7280);
  static const Color _success = Color(0xFF10B981);
  static const Color _warning = Color(0xFFF59E0B);
  static const Color _danger = Color(0xFFEF4444);

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Map<String, dynamic>> _allProducts = [];
  bool _loading = true;
  String? _error;
  String _sortBy = 'name';
  bool _isAscending = true;
  String? _filterCategory;

  late AnimationController _headerCtrl;
  late AnimationController _listCtrl;
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;

  final List<String> _categories = [
    'All',
    'Beverages',
    'Groceries',
    'Snacks',
    'Household',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.scannedBarcode != null) {
      _searchController.text = widget.scannedBarcode!;

      _searchQuery = widget.scannedBarcode!;
    }
    _headerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _listCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _headerFade = CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOut);
    _headerSlide = Tween<Offset>(
      begin: const Offset(0, -0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOutCubic));

    _headerCtrl.forward();
    _loadProducts();
  }

  @override
  void didUpdateWidget(covariant ProductsPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    _loadProducts();

    if (widget.scannedBarcode != null &&
        widget.scannedBarcode != oldWidget.scannedBarcode) {
      _searchController.text = widget.scannedBarcode!;

      setState(() {
        _searchQuery = widget.scannedBarcode!;
      });
    }
  }

  @override
  void dispose() {
    _headerCtrl.dispose();
    _listCtrl.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final products = await DatabaseHelper.instance.getProducts();
      if (!mounted) return;
      setState(() {
        _allProducts = products;
        _loading = false;
      });
      _listCtrl.forward(from: 0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load products: $e';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredProducts {
    final query = _searchQuery.trim().toLowerCase();
    List<Map<String, dynamic>> list = _allProducts.where((p) {
      final name = (p['product_name'] as String? ?? '').toLowerCase();
      final category = (p['category'] as String? ?? '').toLowerCase();

      final barcode = (p['barcode'] as String? ?? '').toLowerCase();

      final matchesQuery =
          name.contains(query) ||
          category.contains(query) ||
          barcode.contains(query);
      final matchesCategory =
          _filterCategory == null ||
          _filterCategory == 'All' ||
          (p['category'] as String? ?? '') == _filterCategory;
      return matchesQuery && matchesCategory;
    }).toList();

    list.sort((a, b) {
      switch (_sortBy) {
        case 'price':
          final pa = (a['price'] as num?)?.toDouble() ?? 0;
          final pb = (b['price'] as num?)?.toDouble() ?? 0;
          return _isAscending ? pa.compareTo(pb) : pb.compareTo(pa);
        case 'stock':
          final sa = (a['stock_quantity'] as int?) ?? 0;
          final sb = (b['stock_quantity'] as int?) ?? 0;
          return _isAscending ? sa.compareTo(sb) : sb.compareTo(sa);
        default:
          final na = (a['product_name'] as String? ?? '').toLowerCase();
          final nb = (b['product_name'] as String? ?? '').toLowerCase();
          return _isAscending ? na.compareTo(nb) : nb.compareTo(na);
      }
    });
    return list;
  }

  // ── Summary stats ──────────────────────────────────────────────────────────
  int get _totalProducts => _allProducts.length;
  int get _lowStockCount => _allProducts
      .where((p) => (p['stock_quantity'] as int? ?? 0) <= 10)
      .length;
  double get _totalValue => _allProducts.fold(
    0.0,
    (sum, p) =>
        sum +
        ((p['price'] as num?)?.toDouble() ?? 0) *
            ((p['stock_quantity'] as int?) ?? 0),
  );

  // ── Helpers ────────────────────────────────────────────────────────────────
  Color _stockColor(int s) {
    if (s == 0) return _danger;
    if (s <= 10) return _warning;
    return _success;
  }

  String _stockLabel(int s) {
    if (s == 0) return 'Out of stock';
    if (s <= 10) return 'Low stock';
    return 'In stock';
  }

  Widget _buildImage(String? path) {
    const double size = 76;
    if (path == null || path.trim().isEmpty) return _imgPlaceholder(size);
    final file = File(path);
    if (file.existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.file(file, width: size, height: size, fit: BoxFit.cover),
      );
    }
    if (path.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.network(
          path,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }
    return _imgPlaceholder(size);
  }

  Widget _imgPlaceholder(double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          _primary.withValues(alpha: 0.08),
          _primary.withValues(alpha: 0.14),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Icon(
      Icons.inventory_2_outlined,
      color: _primary.withValues(alpha: 0.5),
      size: 30,
    ),
  );

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SortSheet(
        currentSort: _sortBy,
        isAscending: _isAscending,
        onSelect: (sort, asc) => setState(() {
          _sortBy = sort;
          _isAscending = asc;
        }),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final products = _filteredProducts;

    return Scaffold(
      backgroundColor: _surface,
      body: SafeArea(
        child: FadeTransition(
          opacity: _headerFade,
          child: SlideTransition(
            position: _headerSlide,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSearchBar(),

                _buildCategoryChips(),

                // ── Product list ─────────────────────────────────────
                Expanded(
                  child: _loading
                      ? _buildLoader()
                      : _error != null
                      ? _buildError()
                      : products.isEmpty
                      ? _buildEmpty()
                      : _buildList(products),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Top header ─────────────────────────────────────────────────────────────
  Widget _buildTopHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
      child: Row(
        children: [
          _ActionBtn(
            icon: Icons.tune_rounded,
            onTap: _showSortSheet,
            tooltip: 'Sort',
          ),
        ],
      ),
    );
  }

  // ── Stats row ──────────────────────────────────────────────────────────────
  Widget _buildStatsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: [
          _StatChip(
            label: 'Total Items',
            value: '$_totalProducts',
            color: _primary,
            icon: Icons.inventory_2_outlined,
          ),
          const SizedBox(width: 10),
          _StatChip(
            label: 'Low Stock',
            value: '$_lowStockCount',
            color: _lowStockCount > 0 ? _warning : _success,
            icon: Icons.warning_amber_rounded,
          ),
          const SizedBox(width: 10),
          _StatChip(
            label: 'Value',
            value: CurrencyFormatter.format(_totalValue),
            color: _success,
            icon: Icons.attach_money_rounded,
            flex: 2,
          ),
        ],
      ),
    );
  }

  // ── Search bar ─────────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (v) => setState(() => _searchQuery = v),
          style: const TextStyle(
            fontSize: 15,
            color: _textPrimary,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: 'Search by name or category...',
            hintStyle: TextStyle(
              fontSize: 14,
              color: _textSecondary.withValues(alpha: 0.55),
              fontWeight: FontWeight.w400,
            ),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 14, right: 10),
              child: Icon(
                Icons.search_rounded,
                color: _textSecondary.withValues(alpha: 0.5),
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
                if (_searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();

                      setState(() {
                        _searchQuery = '';
                      });
                    },

                    child: Container(
                      margin: const EdgeInsets.all(10),

                      decoration: BoxDecoration(
                        color: _textSecondary.withValues(alpha: 0.1),

                        shape: BoxShape.circle,
                      ),

                      child: const Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: _textSecondary,
                      ),
                    ),
                  ),

                GestureDetector(
                  onTap: _showSortSheet,

                  child: Container(
                    margin: const EdgeInsets.only(right: 12),

                    child: const Icon(
                      Icons.tune_rounded,
                      color: _primary,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Category chips ─────────────────────────────────────────────────────────
  Widget _buildCategoryChips() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat = _categories[i];
          final selected =
              (cat == 'All' && _filterCategory == null) ||
              cat == _filterCategory;
          return GestureDetector(
            onTap: () =>
                setState(() => _filterCategory = cat == 'All' ? null : cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? _primary : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: _primary.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Text(
                cat,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Colors.white : _textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Sort label ─────────────────────────────────────────────────────────────
  Widget _buildSortLabel() {
    final labels = {'name': 'Name', 'price': 'Price', 'stock': 'Stock'};
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Row(
        children: [
          Text(
            '${_filteredProducts.length} product${_filteredProducts.length != 1 ? 's' : ''}',
            style: const TextStyle(
              fontSize: 13,
              color: _textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _showSortSheet,
            child: Row(
              children: [
                Icon(
                  _isAscending
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 13,
                  color: _primary,
                ),
                const SizedBox(width: 3),
                Text(
                  labels[_sortBy] ?? 'Name',
                  style: const TextStyle(
                    fontSize: 13,
                    color: _primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Product list ───────────────────────────────────────────────────────────
  Widget _buildList(List<Map<String, dynamic>> products) {
    return RefreshIndicator(
      color: _primary,
      onRefresh: _loadProducts,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),

        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,

          crossAxisSpacing: 12,
          mainAxisSpacing: 12,

          childAspectRatio: 0.72,
        ),
        itemCount: products.length,
        itemBuilder: (_, i) {
          return AnimatedBuilder(
            animation: _listCtrl,
            builder: (_, child) {
              final delay = (i * 0.06).clamp(0.0, 0.5);
              final progress = Curves.easeOutCubic.transform(
                (((_listCtrl.value - delay) / (1 - delay)).clamp(0.0, 1.0)),
              );
              return Opacity(
                opacity: progress,
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - progress)),
                  child: child,
                ),
              );
            },
            child: _buildProductCard(products[i]),
          );
        },
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> p) {
    final name = p['product_name'] as String? ?? 'Unknown';

    final price = (p['price'] as num?)?.toDouble() ?? 0.0;

    final stock = (p['stock_quantity'] as int?) ?? 0;

    final imagePath = p['image_url'] as String?;

    final stockColor = _stockColor(stock);

    return GestureDetector(
      onTap: () async {
        HapticFeedback.lightImpact();

        final updated = widget.onEditProduct?.call(p);

        if (updated == true) {
          _loadProducts();
        }
      },

      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,

          borderRadius: BorderRadius.circular(18),
        ),

        child: Padding(
          padding: const EdgeInsets.all(12),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Expanded(
                child: Center(
                  child: Hero(
                    tag: 'product_${p['id']}',

                    child: _buildImage(imagePath),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              Text(
                name,

                maxLines: 2,

                overflow: TextOverflow.ellipsis,

                style: const TextStyle(
                  fontWeight: FontWeight.w600,

                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                CurrencyFormatter.format(price),

                style: const TextStyle(
                  color: _primary,

                  fontWeight: FontWeight.bold,

                  fontSize: 16,
                ),
              ),

              const SizedBox(height: 8),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,

                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),

                    decoration: BoxDecoration(
                      color: stockColor.withValues(alpha: 0.12),

                      borderRadius: BorderRadius.circular(8),
                    ),

                    child: Text(
                      '$stock pcs',

                      style: TextStyle(
                        fontSize: 11,

                        fontWeight: FontWeight.w600,

                        color: stockColor,
                      ),
                    ),
                  ),

                  Container(
                    width: 34,
                    height: 34,

                    decoration: BoxDecoration(
                      color: const Color(0xFF667EEA),

                      shape: BoxShape.circle,
                    ),

                    child: const Icon(
                      Icons.edit_rounded,

                      color: Colors.white,

                      size: 18,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── States ─────────────────────────────────────────────────────────────────
  Widget _buildLoader() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: _primary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Loading products...',
            style: TextStyle(fontSize: 14, color: _textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _danger.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                color: _danger,
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Failed to load',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: _textSecondary),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _loadProducts,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_primary, Color(0xFF7C4DFF)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Try Again',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: _primary.withValues(alpha: 0.07),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _searchQuery.isNotEmpty
                  ? Icons.search_off_rounded
                  : Icons.inventory_2_outlined,
              color: _primary.withValues(alpha: 0.5),
              size: 42,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty ? 'No results found' : 'No products yet',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _searchQuery.isNotEmpty
                ? 'Try a different search term'
                : 'Add your first product to get started',
            style: const TextStyle(fontSize: 13, color: _textSecondary),
          ),
        ],
      ),
    );
  }
}

// ─── Stat chip ────────────────────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final int flex;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.flex = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
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
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 14),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: color,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10,
                      color: _ProductsPageState._textSecondary,
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

// ─── Action button ────────────────────────────────────────────────────────────
class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _ActionBtn({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        margin: const EdgeInsets.only(right: 8),
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
        child: Tooltip(
          message: tooltip,
          child: Icon(icon, size: 20, color: _ProductsPageState._textSecondary),
        ),
      ),
    );
  }
}

// ─── Sort sheet ───────────────────────────────────────────────────────────────
class _SortSheet extends StatefulWidget {
  final String currentSort;
  final bool isAscending;
  final void Function(String sort, bool asc) onSelect;

  const _SortSheet({
    required this.currentSort,
    required this.isAscending,
    required this.onSelect,
  });

  @override
  State<_SortSheet> createState() => _SortSheetState();
}

class _SortSheetState extends State<_SortSheet> {
  late String _sort;
  late bool _asc;

  static const Color _primary = Color(0xFF5C6BC0);
  static const Color _textPrimary = Color(0xFF1A1F36);
  static const Color _textSecondary = Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    _sort = widget.currentSort;
    _asc = widget.isAscending;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 24),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              const Text(
                'Sort Products',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                  letterSpacing: -0.4,
                ),
              ),
              const Spacer(),
              // Order toggle
              GestureDetector(
                onTap: () => setState(() => _asc = !_asc),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _asc
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 14,
                        color: _primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _asc ? 'Ascending' : 'Descending',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _sortTile(
            'name',
            'Name',
            'A to Z alphabetical',
            Icons.sort_by_alpha_rounded,
          ),
          const SizedBox(height: 10),
          _sortTile(
            'price',
            'Price',
            'By selling price',
            Icons.attach_money_rounded,
          ),
          const SizedBox(height: 10),
          _sortTile(
            'stock',
            'Stock',
            'By quantity available',
            Icons.layers_outlined,
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () {
              widget.onSelect(_sort, _asc);
              Navigator.pop(context);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_primary, Color(0xFF7C4DFF)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
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
    );
  }

  Widget _sortTile(String key, String title, String subtitle, IconData icon) {
    final selected = _sort == key;
    return GestureDetector(
      onTap: () => setState(() => _sort = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? _primary.withValues(alpha: 0.06) : Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? _primary : Colors.grey[200]!,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: selected
                    ? _primary.withValues(alpha: 0.1)
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: selected ? _primary : _textSecondary,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: selected ? _primary : _textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: _textSecondary),
                  ),
                ],
              ),
            ),
            if (selected)
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: _primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
