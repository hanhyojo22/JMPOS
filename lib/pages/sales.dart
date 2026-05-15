import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_app/database/database_helper.dart';
import 'package:pos_app/utils/currency.dart';

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

  const SalesPage({
    super.key,
    this.initialBarcode,
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
  static const Color _textTertiary = Color(0xFFBBBBBB);
  static const Color _success = Color(0xFF10B981);
  static const Color _danger = Color(0xFFEF4444);

  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _selectedCategory = 'All';
  String _selectedSort = 'Default';

  List<Map<String, dynamic>> _allProducts = [];
  final List<Map<String, dynamic>> _cart = [];
  bool _loadingProducts = true;

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

    HapticFeedback.mediumImpact();
    _showSnack('${product['title']} added to cart');

    if (widget.openCartDirectly) {
      Future.delayed(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        _openCartPage();
      });
    }
  }

  // ── Cart ───────────────────────────────────────────────────────────────────
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
  }

  void _deleteFromCart(int index) {
    setState(() {
      final qty = _cart[index]['quantity'] as int;
      _cart[index]['product']['stock'] += qty;
      _cart.removeAt(index);
    });
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
      _showSnack('Sale completed successfully!');
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    }
  }

  // ── Computed ───────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _filteredProducts {
    List<Map<String, dynamic>> list = List.from(_allProducts);

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

  double get _cartTotal => _cart.fold(
    0.0,
    (sum, item) =>
        sum + (item['product']['price'] as num) * (item['quantity'] as int),
  );

  int get _cartQuantity =>
      _cart.fold(0, (sum, item) => sum + (item['quantity'] as int));

  // ── Helpers ────────────────────────────────────────────────────────────────
  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
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
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildProductImage(String? path, {double size = 70}) {
    if (path == null || path.isEmpty) return _placeholder(size);
    final file = File(path);
    if (file.existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
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
        borderRadius: BorderRadius.circular(10),
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
        builder: (_) => CartPage(
          cart: _cart,
          onAdd: _addToCart,
          onRemove: _removeFromCart,
          onDelete: _deleteFromCart,
          onCompleteSale: () async {
            await _completeSale();
            if (mounted) Navigator.pop(context);
          },
        ),
      ),
    ).then((_) => setState(() {}));
  }

  void _showSortSheet() {
    showModalBottomSheet(
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
      backgroundColor: _surface,

      // ── FAB ────────────────────────────────────────────────────────────────
      floatingActionButton: AnimatedScale(
        duration: const Duration(milliseconds: 220),
        scale: _cartQuantity > 0 ? 1 : 0.92,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          opacity: _cartQuantity > 0 ? 1 : 0.7,
          child: GestureDetector(
            onTap: _openCartPage,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_primary, Color(0xFF7C4DFF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _primary.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.shopping_cart_outlined,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                if (_cartQuantity > 0)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _danger,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Text(
                        '$_cartQuantity',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,

      body: SafeArea(
        child: Column(children: [Expanded(child: _buildSaleTab())]),
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
          child: Row(
            children: [
              Expanded(
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
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    style: const TextStyle(
                      fontSize: 14,
                      color: _textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search products...',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: _textSecondary.withValues(alpha: 0.5),
                      ),
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(left: 12, right: 8),
                        child: Icon(
                          Icons.search_rounded,
                          color: _textSecondary.withValues(alpha: 0.5),
                          size: 20,
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 0,
                        minHeight: 0,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                              child: Container(
                                margin: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: _textSecondary.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 15,
                                  color: _textSecondary,
                                ),
                              ),
                            )
                          : null,
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
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _showSortSheet,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _selectedSort != 'Default'
                        ? _primary.withValues(alpha: 0.1)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: _selectedSort != 'Default'
                        ? Border.all(color: _primary.withValues(alpha: 0.4))
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.tune_rounded,
                    color: _selectedSort != 'Default'
                        ? _primary
                        : _textSecondary,
                    size: 20,
                  ),
                ),
              ),
            ],
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
                    color: active ? _primary : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: active
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
                            ),
                          ],
                  ),
                  child: Text(
                    cat,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.white : _textSecondary,
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // Count + cart pill
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
          child: Row(
            children: [
              Text(
                '${products.length} product${products.length != 1 ? 's' : ''}',
                style: const TextStyle(
                  fontSize: 13,
                  color: _textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (_cartQuantity > 0)
                GestureDetector(
                  onTap: _openCartPage,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.shopping_bag_outlined,
                          size: 13,
                          color: _primary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '$_cartQuantity • ${CurrencyFormatter.format(_cartTotal)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Product grid
        Expanded(
          child: _loadingProducts
              ? const Center(child: CircularProgressIndicator(color: _primary))
              : products.isEmpty
              ? _buildEmptyState()
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: products.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.58,
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
    final String category = product['category'] as String? ?? '';
    final _StockState ss = _toStockState(stock);

    final cartItem = _cart.firstWhere(
      (c) => c['product']['id'] == product['id'],
      orElse: () => {},
    );
    final int qty = cartItem.isNotEmpty ? cartItem['quantity'] as int : 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Image area ──────────────────────────────────────────────────
          Stack(
            children: [
              Container(
                height: 120,
                width: double.infinity,
                color: _cardSurface,
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: _buildProductImage(
                    product['imagePath'] as String?,
                    size: 80,
                  ),
                ),
              ),

              // Stock dot
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _stockDotColor(ss),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
            ],
          ),

          // ── Info area ───────────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category label
                  if (category.isNotEmpty) ...[
                    Text(
                      category.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: _textTertiary,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],

                  // Title
                  Text(
                    product['title'] as String,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _textPrimary,
                      height: 1.3,
                    ),
                  ),

                  const SizedBox(height: 6),

                  // Price
                  Text(
                    CurrencyFormatter.format(price),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),

                  const Spacer(),

                  // Divider
                  const Divider(height: 1, thickness: 0.5, color: _border),

                  const SizedBox(height: 8),

                  // Stock badge + action
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Stock badge
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _badgeBg(ss),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            _badgeLabel(stock),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: _badgeFg(ss),
                            ),
                          ),
                        ),
                      ),

                      // Cart action
                      _CardAction(
                        stock: stock,
                        quantity: qty,
                        primary: _primary,
                        surface: _cardSurface,
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
                    ],
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
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _searchQuery.isNotEmpty
                ? 'Try another keyword'
                : 'Add products from inventory',
            style: const TextStyle(fontSize: 13, color: _textSecondary),
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
    required this.onAdd,
    required this.onRemove,
  });

  final int stock;
  final int quantity;
  final Color primary;
  final Color surface;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    // Out of stock
    if (stock == 0) {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(color: surface, shape: BoxShape.circle),
        child: const Icon(
          Icons.block_rounded,
          color: Color(0xFFBBBBBB),
          size: 14,
        ),
      );
    }

    // Add button
    if (quantity == 0) {
      return GestureDetector(
        onTap: onAdd,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
          child: const Icon(Icons.add, color: Colors.white, size: 17),
        ),
      );
    }

    // Stepper
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(shape: BoxShape.circle),
              child: const Icon(
                Icons.remove,
                color: Color(0xFF1A1F36),
                size: 11,
              ),
            ),
          ),
          SizedBox(
            width: 16,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: primary,
              ),
            ),
          ),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
              child: const Icon(Icons.add, color: Colors.white, size: 11),
            ),
          ),
        ],
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
                  letterSpacing: -0.4,
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

// ─── Cart Page ────────────────────────────────────────────────────────────────
class CartPage extends StatefulWidget {
  final List<Map<String, dynamic>> cart;
  final void Function(Map<String, dynamic>) onAdd;
  final void Function(int) onRemove;
  final void Function(int) onDelete;
  final Future<void> Function() onCompleteSale;

  const CartPage({
    super.key,
    required this.cart,
    required this.onAdd,
    required this.onRemove,
    required this.onDelete,
    required this.onCompleteSale,
  });

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  static const Color _primary = Color(0xFF5C6BC0);
  static const Color _textPrimary = Color(0xFF1A1F36);
  static const Color _textSecondary = Color(0xFF6B7280);
  static const Color _success = Color(0xFF10B981);
  static const Color _danger = Color(0xFFEF4444);

  final TextEditingController _cashController = TextEditingController();
  bool _completing = false;

  double get _total => widget.cart.fold(
    0.0,
    (s, i) => s + (i['product']['price'] as num) * (i['quantity'] as int),
  );

  Widget _buildImage(String? path, {double size = 54}) {
    if (path == null || path.isEmpty) return _placeholder(size);
    final file = File(path);
    if (file.existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          file,
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
      color: _primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(
      Icons.inventory_2_outlined,
      color: _primary.withValues(alpha: 0.4),
      size: size * 0.38,
    ),
  );

  void _showPaymentSheet() {
    _cashController.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) {
          final cashAmt = double.tryParse(_cashController.text) ?? 0;
          final change = cashAmt - _total;
          final sufficient = cashAmt >= _total && cashAmt > 0;
          final quickAmounts = _quickCashOptions(_total);

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: EdgeInsets.fromLTRB(
              24,
              0,
              24,
              MediaQuery.of(ctx).viewInsets.bottom + 28,
            ),
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

                // Title row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.payments_outlined,
                        color: _primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Cash Payment',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _textPrimary,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          'Amount due: ${CurrencyFormatter.format(_total)}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: _textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Total banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_primary, Color(0xFF7C4DFF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Amount Due',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        CurrencyFormatter.format(_total),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Cash input
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE8EAF0)),
                  ),
                  child: TextField(
                    controller: _cashController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}'),
                      ),
                    ],
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _textPrimary,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Cash Received',
                      labelStyle: TextStyle(
                        fontSize: 13,
                        color: _textSecondary,
                      ),
                      prefixText: '₱ ',
                      prefixStyle: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _primary,
                      ),
                      filled: false,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    onChanged: (v) => setModal(() {}),
                  ),
                ),
                const SizedBox(height: 12),

                // Quick amounts
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: quickAmounts.map((amt) {
                    return GestureDetector(
                      onTap: () {
                        _cashController.text = amt.toStringAsFixed(0);
                        setModal(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _primary.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          '₱${amt.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _primary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Change display
                if (cashAmt > 0)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: sufficient
                          ? _success.withValues(alpha: 0.07)
                          : _danger.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: sufficient
                            ? _success.withValues(alpha: 0.25)
                            : _danger.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          sufficient
                              ? Icons.check_circle_rounded
                              : Icons.error_rounded,
                          color: sufficient ? _success : _danger,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          sufficient ? 'Change' : 'Insufficient cash',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: sufficient ? _success : _danger,
                          ),
                        ),
                        const Spacer(),
                        if (sufficient)
                          Text(
                            CurrencyFormatter.format(change),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: _success,
                              letterSpacing: -0.5,
                            ),
                          ),
                        if (!sufficient)
                          Text(
                            'Need ${CurrencyFormatter.format(-change)} more',
                            style: TextStyle(
                              fontSize: 12,
                              color: _danger,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),

                const SizedBox(height: 18),

                // Confirm button
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: sufficient && !_completing
                        ? () async {
                            setModal(() {});
                            setState(() => _completing = true);
                            Navigator.pop(ctx);
                            await widget.onCompleteSale();
                            if (mounted) {
                              setState(() => _completing = false);
                            }
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      disabledBackgroundColor: Colors.grey[200],
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: sufficient
                            ? const LinearGradient(
                                colors: [_primary, Color(0xFF7C4DFF)],
                              )
                            : null,
                        color: !sufficient ? Colors.grey[200] : null,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Container(
                        alignment: Alignment.center,
                        child: _completing
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    sufficient
                                        ? 'Confirm Sale  •  Change: ${CurrencyFormatter.format(change)}'
                                        : 'Confirm Sale',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<double> _quickCashOptions(double total) {
    final List<double> options = [];
    final roundings = [1, 5, 10, 20, 50, 100, 200, 500, 1000];
    for (final r in roundings) {
      final rounded = (total / r).ceil() * r.toDouble();
      if (!options.contains(rounded) && options.length < 4) {
        options.add(rounded);
      }
    }
    return options;
  }

  @override
  Widget build(BuildContext context) {
    final cart = widget.cart;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5FF),
      appBar: AppBar(
        title: Column(
          children: [
            const Text(
              'Cart',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: _textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            if (cart.isNotEmpty)
              Text(
                '${cart.length} item${cart.length != 1 ? 's' : ''}',
                style: const TextStyle(
                  fontSize: 12,
                  color: _textSecondary,
                  fontWeight: FontWeight.w400,
                ),
              ),
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: _textPrimary,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F5FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: _textPrimary,
            ),
          ),
        ),
        actions: [
          if (cart.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() {
                for (final item in cart) {
                  item['product']['stock'] += item['quantity'];
                }
                cart.clear();
              }),
              child: Container(
                margin: const EdgeInsets.all(10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Clear',
                  style: TextStyle(
                    color: _danger,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: cart.isEmpty
          ? Center(
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
                      Icons.shopping_cart_outlined,
                      color: _primary.withValues(alpha: 0.45),
                      size: 42,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Cart is empty',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Add products from the sales screen',
                    style: TextStyle(fontSize: 13, color: _textSecondary),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_primary, Color(0xFF7C4DFF)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        'Browse Products',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
              itemCount: cart.length,
              itemBuilder: (ctx, i) {
                final item = cart[i];
                final product = item['product'];
                final String name = product['title'] as String? ?? '';
                final double price = (product['price'] as num).toDouble();
                final int qty = item['quantity'] as int;
                final String? imagePath = product['imagePath'] as String?;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
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
                        _buildImage(imagePath),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: _textPrimary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                CurrencyFormatter.format(price),
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: _primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: () =>
                                        setState(() => widget.onRemove(i)),
                                    child: Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[100],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.remove,
                                        size: 16,
                                        color: _textPrimary,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 50,
                                    child: TextFormField(
                                      initialValue: '$qty',
                                      textAlign: TextAlign.center,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                      ),
                                      onChanged: (val) {
                                        final parsed = int.tryParse(val);
                                        if (parsed != null && parsed > 0) {
                                          setState(
                                            () => widget.cart[i]['quantity'] =
                                                parsed,
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () =>
                                        setState(() => widget.onAdd(product)),
                                    child: Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [_primary, Color(0xFF7C4DFF)],
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.add,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => setState(() => widget.onDelete(i)),
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: _danger.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.delete_outline,
                              color: _danger,
                              size: 17,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${cart.length} item${cart.length != 1 ? 's' : ''}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: _textSecondary,
                          ),
                        ),
                        Row(
                          children: [
                            const Text(
                              'Total  ',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _textSecondary,
                              ),
                            ),
                            Text(
                              CurrencyFormatter.format(_total),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: _primary,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _completing ? null : _showPaymentSheet,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [_primary, Color(0xFF7C4DFF)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Container(
                            alignment: Alignment.center,
                            child: _completing
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.payments_outlined,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Pay Now',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
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
