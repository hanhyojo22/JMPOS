import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pos_app/utils/currency.dart';
import 'package:pos_app/database/database_helper.dart';
import 'package:pos_app/pages/edit_product_page.dart';
import 'package:flutter/services.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Map<String, dynamic>> _allProducts = [];
  bool _loading = true;
  String? _error;

  // Sorting
  String _sortBy = 'name'; // name, price, stock
  bool _isAscending = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
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
      return name.contains(query) || category.contains(query);
    }).toList();

    list.sort((a, b) {
      switch (_sortBy) {
        case 'price':
          final priceA = (a['price'] as num?)?.toDouble() ?? 0;
          final priceB = (b['price'] as num?)?.toDouble() ?? 0;
          return _isAscending
              ? priceA.compareTo(priceB)
              : priceB.compareTo(priceA);
        case 'stock':
          final stockA = (a['stock_quantity'] as int?) ?? 0;
          final stockB = (b['stock_quantity'] as int?) ?? 0;
          return _isAscending
              ? stockA.compareTo(stockB)
              : stockB.compareTo(stockA);
        case 'name':
        default:
          final nameA = (a['product_name'] as String? ?? '').toLowerCase();
          final nameB = (b['product_name'] as String? ?? '').toLowerCase();
          return _isAscending ? nameA.compareTo(nameB) : nameB.compareTo(nameA);
      }
    });

    return list;
  }

  String get _currentSortText {
    String order = _isAscending ? '↑ Ascending' : '↓ Descending';
    switch (_sortBy) {
      case 'price':
        return 'Price $order';
      case 'stock':
        return 'Stock $order';
      default:
        return 'Name $order';
    }
  }

  void _showSortBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'Sort Products',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              _SortOptionTile(
                title: 'Name',
                subtitle: 'Alphabetical order',
                icon: Icons.sort_by_alpha_rounded,
                isSelected: _sortBy == 'name',
                isDescending: !_isAscending,
                onTap: () {
                  setState(() {
                    if (_sortBy == 'name') {
                      _isAscending = !_isAscending;
                    } else {
                      _sortBy = 'name';
                      _isAscending = true;
                    }
                  });
                  Navigator.pop(context);
                },
              ),
              _SortOptionTile(
                title: 'Price',
                subtitle: 'Lowest to highest',
                icon: Icons.attach_money_rounded,
                isSelected: _sortBy == 'price',
                isDescending: !_isAscending,
                onTap: () {
                  setState(() {
                    if (_sortBy == 'price') {
                      _isAscending = !_isAscending;
                    } else {
                      _sortBy = 'price';
                      _isAscending = true;
                    }
                  });
                  Navigator.pop(context);
                },
              ),
              _SortOptionTile(
                title: 'Stock',
                subtitle: 'Quantity available',
                icon: Icons.inventory_2_rounded,
                isSelected: _sortBy == 'stock',
                isDescending: !_isAscending,
                onTap: () {
                  setState(() {
                    if (_sortBy == 'stock') {
                      _isAscending = !_isAscending;
                    } else {
                      _sortBy = 'stock';
                      _isAscending = true;
                    }
                  });
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProductImage(String? imagePath) {
    const double size = 80;
    if (imagePath == null || imagePath.trim().isEmpty) {
      return _placeholder(size);
    }
    final file = File(imagePath);
    if (file.existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.file(file, width: size, height: size, fit: BoxFit.cover),
      );
    }
    if (imagePath.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.network(
          imagePath,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }
    return _placeholder(size);
  }

  Widget _placeholder(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        Icons.inventory_2_outlined,
        color: Colors.grey.shade400,
        size: 32,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Products',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _loading
                            ? 'Loading...'
                            : '${_allProducts.length} items',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      _HeaderBtn(
                        icon: Icons.refresh_rounded,
                        onTap: _loadProducts,
                        tooltip: 'Refresh',
                      ),
                      const SizedBox(width: 8),
                      _HeaderBtn(
                        icon: Icons.sort_rounded,
                        onTap: _showSortBottomSheet,
                        tooltip: 'Sort',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Search
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Search products...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Current Sort
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Sorted by: $_currentSortText',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // List
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? _ErrorState(message: _error!, onRetry: _loadProducts)
                  : _filteredProducts.isEmpty
                  ? _EmptyState(searchQuery: _searchQuery)
                  : RefreshIndicator(
                      onRefresh: _loadProducts,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _filteredProducts.length,
                        itemBuilder: (context, index) {
                          final product = _filteredProducts[index];
                          final name =
                              product['product_name'] as String? ?? 'Unknown';
                          final price =
                              (product['price'] as num?)?.toDouble() ?? 0.0;
                          final stock =
                              (product['stock_quantity'] as int?) ?? 0;
                          final category = product['category'] as String?;
                          final imagePath = product['image_url'] as String?;

                          final status = _getStockStatus(stock);
                          final statusColor = _getStockColor(stock);

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () async {
                                HapticFeedback.lightImpact();
                                final updated = await Navigator.push(
                                  context,
                                  PageRouteBuilder(
                                    transitionDuration: const Duration(
                                      milliseconds: 280,
                                    ),
                                    pageBuilder: (_, animation, _) =>
                                        FadeTransition(
                                          opacity: animation,
                                          child: EditProductPage(
                                            product: product,
                                          ),
                                        ),
                                  ),
                                );
                                if (updated == true) _loadProducts();
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                margin: const EdgeInsets.only(bottom: 14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.04,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      Hero(
                                        tag: 'product_${product['id']}',
                                        child: _buildProductImage(imagePath),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            if (category != null &&
                                                category.isNotEmpty)
                                              Text(
                                                category,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[500],
                                                ),
                                              ),
                                            const SizedBox(height: 8),
                                            Text(
                                              CurrencyFormatter.format(price),
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.blue.shade700,
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            Row(
                                              children: [
                                                _Badge(
                                                  label: status,
                                                  color: statusColor,
                                                ),
                                                const SizedBox(width: 8),
                                                _Badge(
                                                  label: '$stock pcs',
                                                  color: Colors.grey.shade700,
                                                  bgColor: Colors.grey.shade200,
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFF667EEA,
                                          ).withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.edit_outlined,
                                          color: Color(0xFF667EEA),
                                          size: 20,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _getStockStatus(int stock) {
    if (stock == 0) return 'Out of Stock';
    if (stock <= 10) return 'Low Stock';
    return 'In Stock';
  }

  Color _getStockColor(int stock) {
    if (stock == 0) return Colors.red;
    if (stock <= 10) return Colors.orange;
    return Colors.green;
  }
}

// ==================== HELPER WIDGETS ====================

class _HeaderBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _HeaderBtn({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(icon: Icon(icon), onPressed: onTap, tooltip: tooltip),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final Color? bgColor;

  const _Badge({required this.label, required this.color, this.bgColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor ?? color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

// Modern Sort Option Tile
class _SortOptionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final bool isDescending;
  final VoidCallback onTap;

  const _SortOptionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.isDescending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool active = isSelected || isDescending;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF667EEA).withValues(alpha: 0.08)
              : Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? const Color(0xFF667EEA) : Colors.grey.shade200,
            width: active ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFF667EEA).withValues(alpha: 0.1)
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: active ? const Color(0xFF667EEA) : Colors.grey[600],
                size: 26,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: active ? FontWeight.bold : FontWeight.w600,
                      color: active ? const Color(0xFF667EEA) : Colors.black87,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            if (active)
              Icon(
                isDescending
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                color: const Color(0xFF667EEA),
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String searchQuery;
  const _EmptyState({required this.searchQuery});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shopping_bag_outlined,
            size: 72,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            searchQuery.isEmpty
                ? 'No products yet'
                : 'No results for "$searchQuery"',
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: Colors.red.shade300,
            ),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
