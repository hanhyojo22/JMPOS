import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_app/database/database_helper.dart';
import 'package:pos_app/utils/message_banner.dart';

class ProductsPage extends StatefulWidget {
  final String? scannedBarcode;
  final Function(Map<String, dynamic>)? onEditProduct;
  final VoidCallback? onAddProduct;
  final VoidCallback? onBarcodeHandled;
  final List<Map<String, dynamic>> cart;
  final VoidCallback? onCartChanged;
  final String? currentUsername;
  const ProductsPage({
    super.key,
    this.scannedBarcode,
    this.onEditProduct,
    this.onAddProduct,
    this.onBarcodeHandled,
    this.cart = const [],
    this.onCartChanged,
    this.currentUsername,
  });

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage>
    with TickerProviderStateMixin {
  static const Color _primary = Color(0xFF5C6BC0);
  static const Color _surface = Color(0xFFF4F5FF);
  static const Color _textPrimary = Color(0xFF1A1F36);
  static const Color _textSecondary = Color(0xFF6B7280);
  static const Color _success = Color(0xFF10B981);
  static const Color _warning = Color(0xFFF59E0B);
  static const Color _danger = Color(0xFFEF4444);

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _pageSurface => _isDark ? const Color(0xFF0F172A) : _surface;
  Color get _panelSurface => _isDark ? const Color(0xFF111827) : Colors.white;
  Color get _lineColor =>
      _isDark ? const Color(0xFF253047) : Colors.grey.shade200;
  Color get _primaryText => _isDark ? const Color(0xFFF8FAFC) : _textPrimary;
  Color get _secondaryText =>
      _isDark ? const Color(0xFFCBD5E1) : _textSecondary;
  Color get _softShadow => _isDark
      ? Colors.black.withValues(alpha: 0.22)
      : Colors.black.withValues(alpha: 0.04);

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Map<String, dynamic>> _allProducts = [];
  bool _loading = true;
  String? _error;
  String _sortBy = 'Default';
  String? _filterCategory;
  final Set<int> _selectedProductIds = {};
  String? _topMessage;
  bool _topMessageSuccess = false;

  late AnimationController _headerCtrl;
  late AnimationController _listCtrl;
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;

  static const List<String> _categories = [
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
    _applyScannedBarcode();
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

    if (widget.scannedBarcode != null &&
        widget.scannedBarcode != oldWidget.scannedBarcode) {
      _applyScannedBarcode(setStateAfter: true);
    }
  }

  void _applyScannedBarcode({bool setStateAfter = false}) {
    final barcode = widget.scannedBarcode;
    if (barcode == null || barcode.isEmpty) return;

    void apply() {
      _searchController.text = barcode;
      _searchQuery = barcode;
    }

    if (setStateAfter) {
      setState(apply);
    } else {
      apply();
    }

    widget.onBarcodeHandled?.call();
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
        _error = 'Failed to load inventory: $e';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredProducts {
    List<Map<String, dynamic>> list = List.of(_allProducts);

    if (_filterCategory != null && _filterCategory != 'All') {
      list = list
          .where((p) => p['category'].toString() == _filterCategory)
          .toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      list = list.where((p) {
        final name = (p['product_name'] as String? ?? '').toLowerCase();
        final category = (p['category'] as String? ?? '').toLowerCase();
        final barcode = (p['barcode'] as String? ?? '').toLowerCase();

        return name.contains(query) ||
            category.contains(query) ||
            barcode.contains(query);
      }).toList();
    }

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

  Color _stockColor(int s) {
    if (s == 0) return _danger;
    if (s <= 10) return _warning;
    return _success;
  }

  Color _stockBadgeBg(int stock) {
    if (stock == 0) return const Color(0xFFFEE2E2);
    if (stock <= 10) return const Color(0xFFFEF3C7);
    return const Color(0xFFDCFCE7);
  }

  Color _stockBadgeFg(int stock) {
    if (stock == 0) return const Color(0xFFDC2626);
    if (stock <= 10) return const Color(0xFFB45309);
    return const Color(0xFF16A34A);
  }

  String _stockLabel(int stock) {
    if (stock == 0) return 'Out of stock';
    if (stock <= 10) return '$stock left';
    return '$stock stock';
  }

  bool get _isSelecting => _selectedProductIds.isNotEmpty;

  void _toggleProductSelection(Map<String, dynamic> product) {
    final productId = (product['id'] as num?)?.toInt();
    if (productId == null) return;

    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedProductIds.contains(productId)) {
        _selectedProductIds.remove(productId);
      } else {
        _selectedProductIds.add(productId);
      }
    });
  }

  void _clearSelection() {
    if (_selectedProductIds.isEmpty) return;
    setState(_selectedProductIds.clear);
  }

  void _showTopMessage(String message, {bool success = false}) {
    if (!mounted) return;
    setState(() {
      _topMessage = message;
      _topMessageSuccess = success;
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted || _topMessage != message) return;
      setState(() => _topMessage = null);
    });
  }

  List<Map<String, dynamic>> _cartItemsForProductIds(Set<int> productIds) {
    return widget.cart.where((item) {
      final product = item['product'];
      if (product is! Map) return false;
      final productId = (product['id'] as num?)?.toInt();
      return productId != null && productIds.contains(productId);
    }).toList();
  }

  void _removeDeletedProductsFromCart(Set<int> productIds) {
    final beforeCount = widget.cart.length;
    widget.cart.removeWhere((item) {
      final product = item['product'];
      if (product is! Map) return false;
      final productId = (product['id'] as num?)?.toInt();
      return productId != null && productIds.contains(productId);
    });

    if (widget.cart.length != beforeCount) {
      widget.onCartChanged?.call();
    }
  }

  String _deleteSuccessMessage({
    required int selectedCount,
    required bool removedCartItems,
  }) {
    if (removedCartItems) {
      return selectedCount == 1
          ? 'Product deleted and removed from cart'
          : '$selectedCount products deleted and removed from cart';
    }

    return selectedCount == 1
        ? 'Product deleted'
        : '$selectedCount products deleted';
  }

  Future<void> _confirmDeleteSelectedProducts() async {
    final selectedCount = _selectedProductIds.length;
    if (selectedCount == 0) return;
    final idsToDelete = Set<int>.from(_selectedProductIds);
    final cartItemsToRemove = _cartItemsForProductIds(idsToDelete);
    final cartQuantityToRemove = cartItemsToRemove.fold<int>(
      0,
      (total, item) => total + ((item['quantity'] as num?)?.toInt() ?? 0),
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final panel = isDark ? const Color(0xFF111827) : Colors.white;
        final primaryText = isDark ? const Color(0xFFF8FAFC) : _textPrimary;
        final secondaryText = isDark ? const Color(0xFFCBD5E1) : _textSecondary;
        final line = isDark ? const Color(0xFF253047) : Colors.grey.shade200;

        final baseMessage = selectedCount == 1
            ? 'This will remove the selected product.'
            : 'This will remove $selectedCount selected products.';
        String? cartWarning;
        if (cartItemsToRemove.isNotEmpty) {
          cartWarning = selectedCount == 1
              ? 'This product is currently in the cart. If you continue, it will also be removed from the cart.'
              : '$cartQuantityToRemove cart item${cartQuantityToRemove == 1 ? '' : 's'} from the selected products will also be removed from the cart.';
        }

        return AlertDialog(
          backgroundColor: panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            selectedCount == 1 ? 'Delete product?' : 'Delete products?',
            style: TextStyle(color: primaryText, fontWeight: FontWeight.w800),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(baseMessage, style: TextStyle(color: secondaryText)),
              if (cartWarning != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _warning.withValues(alpha: isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _warning.withValues(alpha: isDark ? 0.45 : 0.35),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: _warning,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          cartWarning,
                          style: TextStyle(
                            color: primaryText,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: secondaryText)),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _danger,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: line),
                ),
              ),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    try {
      for (final productId in idsToDelete) {
        await DatabaseHelper.instance.deleteProduct(
          productId,
          actorUsername: widget.currentUsername,
        );
      }
      _removeDeletedProductsFromCart(idsToDelete);
      if (!mounted) return;
      setState(_selectedProductIds.clear);
      _showTopMessage(
        _deleteSuccessMessage(
          selectedCount: selectedCount,
          removedCartItems: cartItemsToRemove.isNotEmpty,
        ),
        success: true,
      );
      await _loadProducts();
    } catch (e) {
      if (!mounted) return;
      _showTopMessage('Failed to delete: $e');
    }
  }

  Widget _buildImage(String? path) {
    final imagePath = path?.trim();
    if (imagePath == null || imagePath.isEmpty) {
      return _imgPlaceholder();
    }

    if (imagePath.startsWith('http')) {
      return Image.network(
        imagePath,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _imgPlaceholder(),
      );
    }

    return Image.file(
      File(imagePath),
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _imgPlaceholder(),
    );
  }

  Widget _imgPlaceholder() => Container(
    width: double.infinity,
    height: double.infinity,
    decoration: BoxDecoration(color: _primary.withValues(alpha: 0.07)),
    child: Icon(
      Icons.image_not_supported_outlined,
      color: _primary.withValues(alpha: 0.4),
      size: 30,
    ),
  );

  void _showSortSheet() {
    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SortSheet(
        current: _sortBy,
        onSelect: (s) => setState(() => _sortBy = s),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = _filteredProducts;

    return Scaffold(
      backgroundColor: _pageSurface,
      floatingActionButton: !_isSelecting && widget.onAddProduct != null
          ? FloatingActionButton(
              heroTag: 'products_add_product',
              onPressed: widget.onAddProduct,
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              elevation: 8,
              tooltip: 'Add product',
              child: const Icon(Icons.add_rounded),
            )
          : null,
      body: Stack(
        children: [
          SafeArea(
            child: FadeTransition(
              opacity: _headerFade,
              child: SlideTransition(
                position: _headerSlide,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSearchBar(),

                    _buildCategoryChips(),
                    if (_isSelecting) _buildSelectionBar(),

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
          if (_topMessage != null)
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: SafeArea(
                bottom: false,
                child: MessageBanner(
                  message: _topMessage!,
                  success: _topMessageSuccess,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSelectionBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _panelSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _primary.withValues(alpha: 0.28)),
          boxShadow: [
            BoxShadow(
              color: _primary.withValues(alpha: _isDark ? 0.18 : 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: _primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${_selectedProductIds.length} selected',
                style: TextStyle(
                  color: _primaryText,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton(
              onPressed: _clearSelection,
              child: Text('Clear', style: TextStyle(color: _secondaryText)),
            ),
            const SizedBox(width: 4),
            ElevatedButton.icon(
              onPressed: _confirmDeleteSelectedProducts,
              style: ElevatedButton.styleFrom(
                backgroundColor: _danger,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
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
          onChanged: (v) => setState(() => _searchQuery = v),
          style: TextStyle(
            fontSize: 14,
            color: _primaryText,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            hintText: 'Search by name or category...',
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
                  message: 'Sort inventory',
                  child: GestureDetector(
                    onTap: _showSortSheet,
                    child: Container(
                      width: 42,
                      height: 42,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: _sortBy != 'Default'
                            ? _primary.withValues(alpha: 0.1)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.tune_rounded,
                        color: _sortBy != 'Default' ? _primary : _secondaryText,
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
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
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
              constraints: const BoxConstraints(minHeight: 38),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: selected ? _primary : _panelSurface,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: selected
                      ? _primary
                      : _secondaryText.withValues(alpha: _isDark ? 0.18 : 0.1),
                  width: 0.5,
                ),
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
                          color: _softShadow,
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Center(
                child: Text(
                  cat,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? Colors.white : _secondaryText,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> products) {
    return RefreshIndicator(
      color: _primary,
      onRefresh: _loadProducts,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const horizontalPadding = 24.0;
          const spacing = 8.0;
          final tileWidth =
              (constraints.maxWidth - horizontalPadding - (spacing * 2)) / 3;

          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 120),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              mainAxisExtent: (tileWidth / 1.02) + 62,
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
          );
        },
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> p) {
    final productId = (p['id'] as num?)?.toInt();
    final isSelected =
        productId != null && _selectedProductIds.contains(productId);
    final name = p['product_name'] as String? ?? 'Unknown';
    final category = (p['category'] as String?)?.trim() ?? '';

    final price = (p['price'] as num?)?.toDouble() ?? 0.0;

    final stock = (p['stock_quantity'] as int?) ?? 0;

    final imagePath = p['image_url'] as String?;

    final stockColor = _stockColor(stock);
    final stockBadgeBg = _stockBadgeBg(stock);
    final stockBadgeFg = _stockBadgeFg(stock);

    return GestureDetector(
      onLongPress: () => _toggleProductSelection(p),
      onTap: () {
        if (_isSelecting) {
          _toggleProductSelection(p);
          return;
        }

        HapticFeedback.lightImpact();
        widget.onEditProduct?.call(p);
      },

      child: Container(
        decoration: BoxDecoration(
          color: _panelSurface,

          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isSelected ? _primary : _lineColor,
            width: isSelected ? 2 : 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? _primary.withValues(alpha: 0.24)
                  : _softShadow,
              blurRadius: isSelected ? 16 : 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,

        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: 1.02,
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: _primary.withValues(
                            alpha: _isDark ? 0.12 : 0.04,
                          ),
                          border: Border(
                            bottom: BorderSide(color: _lineColor, width: 0.5),
                          ),
                        ),
                        child: _buildImage(imagePath),
                      ),
                    ),
                    Positioned(
                      top: 7,
                      right: 7,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: stockBadgeBg,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: stockBadgeFg.withValues(alpha: 0.16),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: stockColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _stockLabel(stock),
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                color: stockBadgeFg,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 7,
                      left: 7,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(
                          color: Color(0xFF667EEA),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.edit_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ],
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 14,
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _primaryText,
                            fontSize: 11,
                            height: 1.12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        category.isEmpty ? 'Product' : category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _secondaryText,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '\u20B1${price.toStringAsFixed(2)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (isSelected) ...[
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _primary.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

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
          Text(
            'Loading inventory...',
            style: TextStyle(fontSize: 14, color: _secondaryText),
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
            Text(
              'Failed to load',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _primaryText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _secondaryText),
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
            _searchQuery.isNotEmpty ? 'No results found' : 'No inventory yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _primaryText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _searchQuery.isNotEmpty
                ? 'Try a different search term'
                : 'Add your first product to start tracking stock',
            style: TextStyle(fontSize: 13, color: _secondaryText),
          ),
        ],
      ),
    );
  }
}

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panel = isDark ? const Color(0xFF111827) : Colors.white;
    final muted = isDark ? const Color(0xFF1E293B) : Colors.grey[50]!;
    final line = isDark ? const Color(0xFF253047) : Colors.grey[200]!;
    final primaryText = isDark ? const Color(0xFFF8FAFC) : _textPrimary;
    final secondaryText = isDark ? const Color(0xFFCBD5E1) : _textSecondary;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: panel,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                    color: line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Sort Inventory',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: primaryText,
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
                              : muted,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected ? _primary : line,
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
                                    : panel,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                opt['icon'] as IconData,
                                color: selected ? _primary : secondaryText,
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
                                      color: selected ? _primary : primaryText,
                                    ),
                                  ),
                                  Text(
                                    opt['sub'] as String,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: secondaryText,
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
      ),
    );
  }
}
