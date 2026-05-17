import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_app/database/database_helper.dart';
import 'package:pos_app/utils/currency.dart';
import 'package:pos_app/utils/message_banner.dart';
import 'shop_cart_page.dart' as shop_cart;

// ─── Stock helpers ────────────────────────────────────────────────────────────
enum _StockState { inStock, lowStock, outOfStock }

_StockState _toStockState(int stock) {
  if (stock == 0) return _StockState.outOfStock;
  if (stock <= 10) return _StockState.lowStock;
  return _StockState.inStock;
}

Color _stockDotColor(_StockState s) => switch (s) {
  _StockState.inStock => const Color(0xFF22C55E),
  _StockState.lowStock => const Color(0xFFF59E0B),
  _StockState.outOfStock => const Color(0xFFEF4444),
};

Color _badgeBg(_StockState s) => switch (s) {
  _StockState.inStock => const Color(0xFFDCFCE7),
  _StockState.lowStock => const Color(0xFFFEF3C7),
  _StockState.outOfStock => const Color(0xFFFEE2E2),
};

Color _badgeFg(_StockState s) => switch (s) {
  _StockState.inStock => const Color(0xFF16A34A),
  _StockState.lowStock => const Color(0xFFB45309),
  _StockState.outOfStock => const Color(0xFFDC2626),
};

String _badgeLabel(int stock) => stock == 0 ? 'Out of stock' : '$stock left';

// ─── SalesPage ────────────────────────────────────────────────────────────────
class SalesPage extends StatefulWidget {
  final bool openCartDirectly;
  final String? initialBarcode;
  final List<Map<String, dynamic>> cart;
  final VoidCallback? onBarcodeHandled;
  final VoidCallback? onCartChanged;
  const SalesPage({
    super.key,
    required this.cart,
    this.initialBarcode,
    this.onBarcodeHandled,
    this.onCartChanged,
    this.openCartDirectly = false,
  });

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  // ── Design tokens ──────────────────────────────────────────────────────────
  static const Color _primary = Color(0xFF5C6BC0);
  static const Color _surface = Color(0xFFF4F5FF);
  static const Color _cardSurface = Color(0xFFF8F8F8);
  static const Color _border = Color(0xFFEEEEEE);
  static const Color _textPrimary = Color(0xFF1A1F36);
  static const Color _textSecondary = Color(0xFF6B7280);

  static const Color _success = Color(0xFF10B981);
  static const Color _danger = Color(0xFFEF4444);

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _pageSurface => _isDark ? const Color(0xFF0F172A) : _surface;
  Color get _panelSurface => _isDark ? const Color(0xFF111827) : Colors.white;
  Color get _mutedSurface => _isDark ? const Color(0xFF1E293B) : _cardSurface;
  Color get _lineColor => _isDark ? const Color(0xFF253047) : _border;
  Color get _primaryText => _isDark ? const Color(0xFFF8FAFC) : _textPrimary;
  Color get _secondaryText =>
      _isDark ? const Color(0xFFCBD5E1) : _textSecondary;
  Color get _softShadow => _isDark
      ? Colors.black.withValues(alpha: 0.22)
      : Colors.black.withValues(alpha: 0.04);

  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _selectedCategory = 'All';
  String _selectedSort = 'Default';

  List<Map<String, dynamic>> _allProducts = [];
  late List<Map<String, dynamic>> _cart;
  bool _loadingProducts = true;
  bool _barcodeHandled = false;
  String? _topMessage;
  bool _topMessageSuccess = true;

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
    _cart = widget.cart;
    _loadProducts().then((_) => _handleInitialBarcode());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────────────────
  Future<void> _loadProducts() async {
    setState(() => _loadingProducts = true);
    final db = await DatabaseHelper.instance.database;
    final products = await db.query('products');
    if (!mounted) return;
    setState(() {
      _allProducts = products
          .map(
            (p) => {
              'id': p['id'],
              'title': p['product_name'],
              'price': p['price'],
              'stock': p['stock_quantity'],
              'barcode': p['barcode'] ?? '',
              'imagePath': p['image_url'] ?? '',
              'category': p['category'] ?? 'Other',
            },
          )
          .toList();
      _loadingProducts = false;
    });
  }

  void _handleInitialBarcode() {
    if (_barcodeHandled) return;

    final barcode = widget.initialBarcode;
    if (barcode == null || barcode.isEmpty) return;

    final productIndex = _allProducts.indexWhere(
      (p) => p['barcode'].toString() == barcode,
    );

    if (productIndex == -1) {
      _showSnack('Product not found', isError: true);
      return;
    }

    final product = _allProducts[productIndex];
    final cartIndex = _cart.indexWhere(
      (i) => i['product']['id'] == product['id'],
    );

    setState(() {
      if (cartIndex != -1) {
        _cart[cartIndex]['quantity'] += 1;
      } else {
        _cart.add({'product': product, 'quantity': 1});
      }
    });
    _notifyCartChanged();

    _barcodeHandled = true;
    widget.onBarcodeHandled?.call();
    HapticFeedback.mediumImpact();
    _showSnack('${product['title']} added to cart', top: true);

    if (widget.openCartDirectly) {
      Future.delayed(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        _openCartPage();
      });
    }
  }

  // ── Cart ───────────────────────────────────────────────────────────────────
  void _notifyCartChanged() => widget.onCartChanged?.call();

  void _addToCart(Map<String, dynamic> product) {
    if ((product['stock'] as int) <= 0) return;
    final idx = _cart.indexWhere((i) => i['product']['id'] == product['id']);
    setState(() {
      product['stock'] = (product['stock'] as int) - 1;
      if (idx != -1) {
        _cart[idx]['quantity'] += 1;
      } else {
        _cart.add({'product': product, 'quantity': 1});
      }
    });
    _notifyCartChanged();
    _showSnack('${product['title']} added to cart', top: true);
  }

  void _removeFromCart(int index) {
    setState(() {
      _cart[index]['product']['stock'] += 1;
      if (_cart[index]['quantity'] > 1) {
        _cart[index]['quantity'] -= 1;
      } else {
        _cart.removeAt(index);
      }
    });
    _notifyCartChanged();
  }

  void _deleteFromCart(int index) {
    setState(() {
      final qty = _cart[index]['quantity'] as int;
      _cart[index]['product']['stock'] += qty;
      _cart.removeAt(index);
    });
    _notifyCartChanged();
  }

  Future<void> _completeSale() async {
    if (_cart.isEmpty) return;
    final db = await DatabaseHelper.instance.database;
    try {
      for (final item in _cart) {
        final product = item['product'];
        final int quantity = item['quantity'];
        final double price = (product['price'] as num).toDouble();
        await db.insert('sales', {
          'product_id': product['id'],
          'product_name': product['title'],
          'quantity': quantity,
          'price': price,
          'total': price * quantity,
          'created_at': DateTime.now().toIso8601String(),
        });
        await db.update(
          'products',
          {
            'stock_quantity': product['stock'],
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [product['id']],
        );
      }
      _cart.clear();
      await _loadProducts();
      setState(() {});
      _notifyCartChanged();
      _showSnack('Sale completed successfully!', top: true);
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    }
  }

  // ── Computed ───────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _filteredProducts {
    List<Map<String, dynamic>> list = List.from(_allProducts);
    list = list.where((p) {
      final inCart = _cart.any((i) => i['product']['id'] == p['id']);
      return (p['stock'] as int) > 0 || inCart;
    }).toList();

    if (_selectedCategory != 'All') {
      list = list
          .where((p) => p['category'].toString() == _selectedCategory)
          .toList();
    }

    if (_searchQuery.isNotEmpty) {
      list = list
          .where(
            (p) => p['title'].toString().toLowerCase().contains(
              _searchQuery.toLowerCase(),
            ),
          )
          .toList();
    }

    switch (_selectedSort) {
      case 'A → Z':
        list.sort(
          (a, b) => a['title'].toString().compareTo(b['title'].toString()),
        );
        break;
      case 'Price ↑':
        list.sort((a, b) => (a['price'] as num).compareTo(b['price'] as num));
        break;
      case 'Price ↓':
        list.sort((a, b) => (b['price'] as num).compareTo(a['price'] as num));
        break;
      case 'Stock ↓':
        list.sort((a, b) => (b['stock'] as int).compareTo(a['stock'] as int));
        break;
    }

    return list;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  void _showSnack(String msg, {bool isError = false, bool top = false}) {
    if (!mounted) return;
    if (top) {
      setState(() {
        _topMessage = msg;
        _topMessageSuccess = !isError;
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted || _topMessage != msg) return;
        setState(() => _topMessage = null);
      });
      return;
    }

    final media = MediaQuery.of(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(msg, overflow: TextOverflow.ellipsis)),
          ],
        ),
        backgroundColor: isError ? _danger : _success,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          left: 60,
          right: 60,
          bottom: 90 + media.padding.bottom,
        ),
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildProductImage(
    String? path, {
    double size = 70,
    double borderRadius = 10,
  }) {
    if (path == null || path.isEmpty) return _placeholder(size);
    final file = File(path);
    if (file.existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _placeholder(size),
        ),
      );
    }
    if (path.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.network(
          path,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _placeholder(size),
        ),
      );
    }
    return _placeholder(size);
  }

  Widget _placeholder(double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: _primary.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(
      Icons.inventory_2_outlined,
      color: _primary.withValues(alpha: 0.4),
      size: size * 0.38,
    ),
  );

  // ── Navigation ─────────────────────────────────────────────────────────────
  void _openCartPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => shop_cart.CartPage(
          cart: _cart,
          onAdd: _addToCart,
          onRemove: _removeFromCart,
          onDelete: _deleteFromCart,
          onCompleteSale: () async {
            await _completeSale();
          },
        ),
      ),
    ).then((_) => setState(() {}));
  }

  void _showSortSheet() {
    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SortSheet(
        current: _selectedSort,
        onSelect: (s) => setState(() => _selectedSort = s),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageSurface,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,

      body: Stack(
        children: [
          SafeArea(
            child: Column(children: [Expanded(child: _buildSaleTab())]),
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

  // ── Header ─────────────────────────────────────────────────────────────────

  // ── Sale tab ───────────────────────────────────────────────────────────────
  Widget _buildSaleTab() {
    final products = _filteredProducts;

    return Column(
      children: [
        // Search + sort
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
              onChanged: (v) => setState(() => _searchQuery = v),
              style: TextStyle(
                fontSize: 15,
                color: _primaryText,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: 'Search products...',
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
                          setState(() => _searchQuery = '');
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
                      message: 'Sort products',
                      child: GestureDetector(
                        onTap: _showSortSheet,
                        child: Container(
                          width: 42,
                          height: 42,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: _selectedSort != 'Default'
                                ? _primary.withValues(alpha: 0.1)
                                : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.tune_rounded,
                            color: _selectedSort != 'Default'
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
                filled: false,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
              ),
            ),
          ),
        ),

        // Category chips
        SizedBox(
          height: 46,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            scrollDirection: Axis.horizontal,
            itemCount: _categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final cat = _categories[i];
              final active = cat == _selectedCategory;
              return GestureDetector(
                onTap: () => setState(() => _selectedCategory = cat),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: active ? _primary : _panelSurface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: _primary.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : [BoxShadow(color: _softShadow, blurRadius: 6)],
                  ),
                  child: Text(
                    cat,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.white : _secondaryText,
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // Product grid
        Expanded(
          child: _loadingProducts
              ? const Center(child: CircularProgressIndicator(color: _primary))
              : products.isEmpty
              ? _buildEmptyState()
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: products.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.62,
                  ),
                  itemBuilder: (_, i) => _buildProductCard(products[i]),
                ),
        ),
      ],
    );
  }

  // ── Product card (new design) ──────────────────────────────────────────────
  Widget _buildProductCard(Map<String, dynamic> product) {
    final int stock = product['stock'] as int;
    final double price = (product['price'] as num).toDouble();

    final _StockState ss = _toStockState(stock);

    final cartItem = _cart.firstWhere(
      (c) => c['product']['id'] == product['id'],
      orElse: () => {},
    );
    final int qty = cartItem.isNotEmpty ? cartItem['quantity'] as int : 0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _panelSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: qty > 0 ? _primary.withValues(alpha: 0.28) : _lineColor,
          width: qty > 0 ? 1 : 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: qty > 0 ? _primary.withValues(alpha: 0.12) : _softShadow,
            blurRadius: qty > 0 ? 16 : 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Container(
                height: 126,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _primary.withValues(alpha: _isDark ? 0.12 : 0.04),
                  border: Border(
                    bottom: BorderSide(color: _lineColor, width: 0.5),
                  ),
                ),
                child: SizedBox.expand(
                  child: _buildProductImage(
                    product['imagePath'] as String?,
                    borderRadius: 0,
                    size: double.infinity,
                  ),
                ),
              ),

              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _badgeBg(ss),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: _badgeFg(ss).withValues(alpha: 0.16),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _stockDotColor(ss),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _badgeLabel(stock),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: _badgeFg(ss),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product['title'] as String,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _primaryText,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    CurrencyFormatter.format(price),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: _primaryText,
                      letterSpacing: -0.3,
                    ),
                  ),

                  const SizedBox(height: 8),

                  SizedBox(
                    width: double.infinity,
                    child: _CardAction(
                      stock: stock,
                      quantity: qty,
                      primary: _primary,
                      surface: _mutedSurface,
                      lineColor: _lineColor,
                      onAdd: () {
                        HapticFeedback.lightImpact();
                        _addToCart(product);
                      },
                      onRemove: () {
                        HapticFeedback.lightImpact();
                        final idx = _cart.indexWhere(
                          (c) => c['product']['id'] == product['id'],
                        );
                        if (idx != -1) _removeFromCart(idx);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
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
              color: _primary.withValues(alpha: 0.45),
              size: 42,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? 'No products found'
                : 'No products available',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _primaryText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _searchQuery.isNotEmpty
                ? 'Try another keyword'
                : 'Add products from inventory',
            style: TextStyle(fontSize: 13, color: _secondaryText),
          ),
        ],
      ),
    );
  }
}

// ─── Card action widget ───────────────────────────────────────────────────────
class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.stock,
    required this.quantity,
    required this.primary,
    required this.surface,
    required this.lineColor,
    required this.onAdd,
    required this.onRemove,
  });

  final int stock;
  final int quantity;
  final Color primary;
  final Color surface;
  final Color lineColor;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final canAdd = stock > 0;

    if (quantity > 0) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 40,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: primary.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            _QuantityButton(
              icon: Icons.remove_rounded,
              foreground: primary,
              background: Colors.white,
              borderColor: lineColor,
              onTap: onRemove,
              tooltip: 'Remove one',
            ),
            Expanded(
              child: Text(
                '$quantity',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: primary,
                ),
              ),
            ),
            _QuantityButton(
              icon: canAdd ? Icons.add_rounded : Icons.check_rounded,
              foreground: canAdd ? Colors.white : primary,
              background: canAdd ? primary : primary.withValues(alpha: 0.12),
              borderColor: Colors.transparent,
              onTap: canAdd ? onAdd : null,
              tooltip: canAdd ? 'Add one more' : 'All stock added',
            ),
          ],
        ),
      );
    }

    // Out of stock
    if (!canAdd) {
      return Container(
        width: double.infinity,
        height: 40,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: lineColor),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.block_rounded, color: Color(0xFFBBBBBB), size: 17),
            SizedBox(width: 8),
            Text(
              'Out of stock',
              style: TextStyle(
                color: Color(0xFF8A8A8A),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    // Add button
    return GestureDetector(
      onTap: onAdd,
      child: Container(
        width: double.infinity,
        height: 40,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [primary, const Color(0xFF7C4DFF)]),
          borderRadius: BorderRadius.circular(13),
          boxShadow: [
            BoxShadow(
              color: primary.withValues(alpha: 0.28),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_shopping_cart_rounded,
              color: Colors.white,
              size: 18,
            ),
            SizedBox(width: 8),
            Text(
              'Add to Cart',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuantityButton extends StatelessWidget {
  const _QuantityButton({
    required this.icon,
    required this.foreground,
    required this.background,
    required this.borderColor,
    required this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final Color foreground;
  final Color background;
  final Color borderColor;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: CircleBorder(side: BorderSide(color: borderColor, width: 0.5)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, color: foreground, size: 18),
          ),
        ),
      ),
    );
  }
}

// ─── Sort Sheet ───────────────────────────────────────────────────────────────
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
                  'Sort Products',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: primaryText,
                    letterSpacing: -0.4,
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
