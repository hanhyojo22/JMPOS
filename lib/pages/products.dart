import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_app/utils/currency.dart';
import 'package:pos_app/database/database_helper.dart';

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
  String _sortBy = 'Default';
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
    List<Map<String, dynamic>> list = List.from(_allProducts);

    // Category filter
    if (_filterCategory != null && _filterCategory != 'All') {
      list = list
          .where((p) => p['category'].toString() == _filterCategory)
          .toList();
    }

    // Search
    if (_searchQuery.isNotEmpty) {
      list = list.where((p) {
        final name = (p['product_name'] as String? ?? '').toLowerCase();

        final category = (p['category'] as String? ?? '').toLowerCase();

        final barcode = (p['barcode'] as String? ?? '').toLowerCase();

        final query = _searchQuery.toLowerCase();

        return name.contains(query) ||
            category.contains(query) ||
            barcode.contains(query);
      }).toList();
    }

    // Sort
    switch (_sortBy) {
      case 'A → Z':
        list.sort(
          (a, b) => (a['product_name'] as String).compareTo(
            b['product_name'] as String,
          ),
        );
        break;

      case 'Price ↑':
        list.sort((a, b) => (a['price'] as num).compareTo(b['price'] as num));
        break;

      case 'Price ↓':
        list.sort((a, b) => (b['price'] as num).compareTo(a['price'] as num));
        break;

      case 'Stock ↓':
        list.sort(
          (a, b) => (b['stock_quantity'] as int).compareTo(
            a['stock_quantity'] as int,
          ),
        );
        break;
    }

    return list;
  }

  // ── Summary stats ──────────────────────────────────────────────────────────

  // ── Helpers ────────────────────────────────────────────────────────────────
  Color _stockColor(int s) {
    if (s == 0) return _danger;
    if (s <= 10) return _warning;
    return _success;
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
        current: _sortBy,
        onSelect: (s) => setState(() => _sortBy = s),
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

  // ── Stats row ──────────────────────────────────────────────────────────────

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
        separatorBuilder: (_, _) => const SizedBox(width: 8),
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

// ─── Action button ────────────────────────────────────────────────────────────

// ─── Sort sheet ───────────────────────────────────────────────────────────────

class _SortSheet extends StatefulWidget {
  final String current;
  final void Function(String) onSelect;

  const _SortSheet({required this.current, required this.onSelect});

  @override
  State<_SortSheet> createState() => _SortSheetState();
}

class _SortSheetState extends State<_SortSheet> {
  static const Color _primary = Color(0xFF5C6BC0);
  static const Color _textPrimary = Color(0xFF1A1F36);
  static const Color _textSecondary = Color(0xFF6B7280);

  late String _selected;

  final _options = [
    {
      'key': 'Default',
      'label': 'Default',
      'sub': 'As added to inventory',
      'icon': Icons.list_rounded,
    },
    {
      'key': 'A → Z',
      'label': 'Name A → Z',
      'sub': 'Alphabetical order',
      'icon': Icons.sort_by_alpha_rounded,
    },
    {
      'key': 'Price ↑',
      'label': 'Price Low → High',
      'sub': 'Cheapest first',
      'icon': Icons.arrow_upward_rounded,
    },
    {
      'key': 'Price ↓',
      'label': 'Price High → Low',
      'sub': 'Most expensive first',
      'icon': Icons.arrow_downward_rounded,
    },
    {
      'key': 'Stock ↓',
      'label': 'Stock High → Low',
      'sub': 'Most available first',
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
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
      child: SingleChildScrollView(
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
                'Sort Products',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                ),
              ),
            ),

            const SizedBox(height: 18),

            ..._options.map((opt) {
              final selected = _selected == opt['key'];

              return GestureDetector(
                onTap: () => setState(() => _selected = opt['key'] as String),
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
            }),

            const SizedBox(height: 12),

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
    );
  }
}
