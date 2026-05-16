import 'dart:io';
import 'history_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'add_products.dart';
import 'products.dart';
import 'sales.dart';
import 'reports.dart';
import 'account_page.dart';
import 'staff_management.dart';
import 'package:pos_app/utils/greetings.dart';
import 'package:pos_app/database/database_helper.dart';
import 'package:pos_app/utils/currency.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'edit_product_page.dart';
import 'setting_page.dart';
import 'login.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.title,
    required this.username,
    required this.role,
  });

  final String username;
  final String title;
  final String role;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<Map<String, dynamic>> sharedCart = [];
  String? addProductScannedBarcode;
  int _selectedIndex = 0;
  String? salesScannedBarcode;
  final int _salesBarcodeScanVersion = 0;
  String? productsScannedBarcode;
  String? addProductBarcode;
  Map<String, dynamic>? selectedProduct;
  double totalSales = 0;
  int totalTransactions = 0;
  List<Map<String, dynamic>> recentTransactions = [];
  bool _loadingHome = true;

  @override
  void initState() {
    super.initState();
    loadRecentTransactions();
  }

  Future<void> loadRecentTransactions() async {
    setState(() => _loadingHome = true);
    try {
      final db = await DatabaseHelper.instance.database;

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1));

      final totalResult = await db.rawQuery(
        '''
        SELECT
          COALESCE(SUM(total), 0)  AS grand_total,
          COUNT(*)                 AS total_count
        FROM sales
        WHERE created_at >= ? AND created_at < ?
      ''',
        [todayStart.toIso8601String(), todayEnd.toIso8601String()],
      );

      final transactions = await db.rawQuery('''
        SELECT
          sales.id,
          sales.product_name,
          sales.total,
          sales.quantity,
          sales.created_at,
          products.image_url
        FROM sales
        LEFT JOIN products ON sales.product_id = products.id
        ORDER BY sales.created_at DESC
        LIMIT 10
      ''');

      final double salesTotal =
          (totalResult.first['grand_total'] as num?)?.toDouble() ?? 0.0;
      final int transactionCount =
          (totalResult.first['total_count'] as num?)?.toInt() ?? 0;

      setState(() {
        totalSales = salesTotal;
        totalTransactions = transactionCount;

        recentTransactions = transactions.map((sale) {
          DateTime? createdAt;
          try {
            createdAt = DateTime.parse(sale['created_at'].toString()).toLocal();
          } catch (_) {}

          String subtitle = '';
          if (createdAt != null) {
            final saleDate = DateTime(
              createdAt.year,
              createdAt.month,
              createdAt.day,
            );
            final h = createdAt.hour % 12 == 0 ? 12 : createdAt.hour % 12;
            final m = createdAt.minute.toString().padLeft(2, '0');
            final period = createdAt.hour >= 12 ? 'PM' : 'AM';
            final timeStr = '$h:$m $period';

            if (saleDate == todayStart) {
              subtitle = 'Today • $timeStr';
            } else if (saleDate ==
                todayStart.subtract(const Duration(days: 1))) {
              subtitle = 'Yesterday • $timeStr';
            } else {
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
              subtitle =
                  '${months[createdAt.month - 1]} ${createdAt.day} • $timeStr';
            }
          }

          return {
            'title': sale['product_name'] ?? 'Unknown',
            'subtitle': subtitle,
            'amount': (sale['total'] as num?)?.toDouble() ?? 0.0,
            'quantity': sale['quantity'] ?? 0,
            'imagePath': sale['image_url'] ?? '',
          };
        }).toList();

        _loadingHome = false;
      });
    } catch (e) {
      debugPrint('loadRecentTransactions error: $e');
      setState(() => _loadingHome = false);
    }
  }

  void _openAccount() {
    setState(() => _selectedIndex = 10);
  }

  // ── Step 1: open scanner  Step 2: if barcode captured → open SalesPage ──────
  Future<void> _openScannerAction() async {
    String? scannedBarcode;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _QuickScannerPage(
          onDetect: (code) {
            scannedBarcode = code;
          },
        ),
      ),
    );

    if (!mounted || scannedBarcode == null) {
      return;
    }

    // PRODUCTS PAGE
    if (_selectedIndex == 1) {
      setState(() {
        productsScannedBarcode = scannedBarcode;
      });

      return;
    }

    // ADD PRODUCT PAGE
    if (_selectedIndex == 2) {
      setState(() {
        addProductBarcode = scannedBarcode;
      });

      return;
    }

    // EDIT PRODUCT PAGE
    if (_selectedIndex == 8) {
      setState(() {
        addProductBarcode = scannedBarcode;
      });

      return;
    }

    final added = await _addScannedBarcodeToSharedCart(scannedBarcode!);
    if (!mounted || !added) return;

    _openCartPage();
  }

  Widget _buildProductImage(String imagePath) {
    if (imagePath.isEmpty) {
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.shopping_bag_outlined,
          color: Colors.grey.shade400,
          size: 26,
        ),
      );
    }
    final file = File(imagePath);
    if (file.existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          file,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _imageFallback(),
        ),
      );
    }
    return _imageFallback();
  }

  Widget _imageFallback() => Container(
    width: 56,
    height: 56,
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(
      Icons.shopping_bag_outlined,
      color: Colors.grey.shade400,
      size: 26,
    ),
  );

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<bool> _addScannedBarcodeToSharedCart(String barcode) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'products',
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );

    if (!mounted) return false;

    if (rows.isEmpty) {
      _showSnack('Product not found', isError: true);
      return false;
    }

    final productRow = rows.first;
    final productId = productRow['id'];
    final productName = productRow['product_name']?.toString() ?? 'Product';
    final cartIndex = sharedCart.indexWhere(
      (item) => item['product']['id'] == productId,
    );

    if (cartIndex != -1) {
      final cartProduct =
          sharedCart[cartIndex]['product'] as Map<String, dynamic>;
      final stock = (cartProduct['stock'] as num?)?.toInt() ?? 0;

      if (stock <= 0) {
        _showSnack('$productName is out of stock', isError: true);
        return false;
      }

      setState(() {
        cartProduct['stock'] = stock - 1;
        sharedCart[cartIndex]['quantity'] += 1;
      });
    } else {
      final stock = (productRow['stock_quantity'] as num?)?.toInt() ?? 0;

      if (stock <= 0) {
        _showSnack('$productName is out of stock', isError: true);
        return false;
      }

      final product = {
        'id': productId,
        'title': productName,
        'price': productRow['price'],
        'stock': stock - 1,
        'barcode': productRow['barcode'] ?? '',
        'imagePath': productRow['image_url'] ?? '',
        'category': productRow['category'] ?? 'Other',
      };

      setState(() {
        sharedCart.add({'product': product, 'quantity': 1});
      });
    }

    HapticFeedback.mediumImpact();
    _showSnack('$productName added to cart');
    return true;
  }

  void _addToSharedCart(Map<String, dynamic> product) {
    final stock = (product['stock'] as num?)?.toInt() ?? 0;
    if (stock <= 0) return;

    final index = sharedCart.indexWhere(
      (item) => item['product']['id'] == product['id'],
    );

    setState(() {
      product['stock'] = stock - 1;
      if (index != -1) {
        sharedCart[index]['quantity'] += 1;
      } else {
        sharedCart.add({'product': product, 'quantity': 1});
      }
    });
  }

  void _removeFromSharedCart(int index) {
    if (index < 0 || index >= sharedCart.length) return;

    setState(() {
      sharedCart[index]['product']['stock'] += 1;
      if (sharedCart[index]['quantity'] > 1) {
        sharedCart[index]['quantity'] -= 1;
      } else {
        sharedCart.removeAt(index);
      }
    });
  }

  void _deleteFromSharedCart(int index) {
    if (index < 0 || index >= sharedCart.length) return;

    setState(() {
      final quantity = sharedCart[index]['quantity'] as int;
      sharedCart[index]['product']['stock'] += quantity;
      sharedCart.removeAt(index);
    });
  }

  Future<bool> _completeSharedSale() async {
    if (sharedCart.isEmpty) return false;

    final db = await DatabaseHelper.instance.database;
    try {
      for (final item in sharedCart) {
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

      sharedCart.clear();
      await loadRecentTransactions();
      if (mounted) setState(() {});
      _showSnack('Sale completed successfully!');
      return true;
    } catch (e) {
      _showSnack('Error: $e', isError: true);
      return false;
    }
  }

  void _openCartPage() {
    setState(() => _selectedIndex = 9);
  }

  Widget _buildPageContent() {
    switch (_selectedIndex) {
      case 1:
        return ProductsPage(
          scannedBarcode: productsScannedBarcode,

          onEditProduct: (product) {
            setState(() {
              selectedProduct = product;
              _selectedIndex = 8;
            });
          },
        );

      case 2:
        return AddProductsPage(
          key: ValueKey(addProductBarcode),
          initialBarcode: addProductBarcode,
        );

      case 3:
        return SalesPage(
          key: ValueKey(
            '${salesScannedBarcode ?? 'sales'}_$_salesBarcodeScanVersion',
          ),

          cart: sharedCart,
          onBarcodeHandled: () {
            salesScannedBarcode = null;
          },
          onCartChanged: () {
            if (mounted) setState(() {});
          },
          initialBarcode: salesScannedBarcode,

          openCartDirectly: salesScannedBarcode != null,
        );

      case 4:
        if (widget.role == 'admin') {
          return const ReportsPage();
        }
        return SalesPage(
          cart: sharedCart,
          onCartChanged: () {
            if (mounted) setState(() {});
          },
        );

      case 5:
        if (widget.role == 'admin') {
          return const StaffManagementPage();
        }
        break;

      case 6:
        return const HistoryPage();

      case 7:
        return const SettingsPage();
      case 8:
        if (selectedProduct == null) {
          return const Center(child: Text('No product selected'));
        }

        return EditProductPage(
          key: ValueKey(selectedProduct!['id']),

          product: selectedProduct!,

          onBack: () {
            setState(() {
              _selectedIndex = 1;
            });
          },

          onSaved: () {
            setState(() {
              productsScannedBarcode = null;
              _selectedIndex = 1;
            });
          },
        );

      case 9:
        return CartPage(
          cart: sharedCart,
          showAppBar: false,
          onAdd: _addToSharedCart,
          onRemove: _removeFromSharedCart,
          onDelete: _deleteFromSharedCart,
          onCompleteSale: () async {
            await _completeSharedSale();
          },
          onBrowseProducts: () {
            setState(() => _selectedIndex = 3);
          },
        );

      case 10:
        return AccountPage(username: widget.username);
    }

    // ── Home tab ─────────────────────────────────────────────────────────────
    return RefreshIndicator(
      onRefresh: loadRecentTransactions,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Revenue card ──────────────────────────────────────
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(24),
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF667EEA).withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: _loadingHome
                  ? const SizedBox(
                      height: 120,
                      child: Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Today's Revenue",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  Greetings.getTodayDate(),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.75),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.trending_up,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          CurrencyFormatter.format(totalSales),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: _StatPill(
                                icon: Icons.receipt_long,
                                label: 'Transactions',
                                value: '$totalTransactions',
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _StatPill(
                                icon: Icons.calculate_outlined,
                                label: 'Avg. Order',
                                value: CurrencyFormatter.format(
                                  totalTransactions == 0
                                      ? 0
                                      : totalSales / totalTransactions,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),

            // ── Recent Transactions header ────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Recent Transactions',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _selectedIndex = 3),
                    child: const Text('View all'),
                  ),
                ],
              ),
            ),

            // ── Transaction list ─────────────────────────────────
            if (_loadingHome)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (recentTransactions.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 56,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No transactions today',
                        style: TextStyle(fontSize: 15, color: Colors.grey[500]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Completed sales will appear here',
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: recentTransactions.map((t) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
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
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        leading: _buildProductImage(t['imagePath'] as String),
                        title: Text(
                          t['title'] as String,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          t['subtitle'] as String,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              CurrencyFormatter.format(t['amount'] as double),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Color(0xFF667EEA),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'x${t['quantity']}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[400],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _onNavBarTapped(int index) async {
    setState(() => _selectedIndex = index);
    if (index == 0) await loadRecentTransactions();
  }

  Widget _drawerItem({
    required IconData icon,
    required String title,
    required int index,
  }) {
    final bool active = _selectedIndex == index;

    return ListTile(
      leading: Icon(
        icon,
        color: active ? const Color(0xFF667EEA) : Colors.grey,
      ),

      title: Text(
        title,

        style: TextStyle(
          fontWeight: active ? FontWeight.bold : FontWeight.w500,

          color: active ? const Color(0xFF667EEA) : Colors.black87,
        ),
      ),

      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),

      selected: active,

      onTap: () {
        Navigator.pop(context);

        setState(() {
          _selectedIndex = index;
        });

        if (index == 0) {
          loadRecentTransactions();
        }
      },
    );
  }

  Widget _scannerFab({Offset offset = Offset.zero}) => GestureDetector(
    onTap: _openScannerAction,
    child: Transform.translate(
      offset: offset,
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF667EEA).withValues(alpha: 0.45),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Icon(
          Icons.qr_code_scanner_rounded,
          color: Colors.white,
          size: 32,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded),

            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
          ),
        ),
        title: Row(
          children: [
            Text(Greetings.getGreeting()),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: widget.role == 'admin'
                    ? Colors.red.withValues(alpha: 0.15)
                    : Colors.blue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.role.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: widget.role == 'admin'
                      ? Colors.red[700]
                      : Colors.blue[700],
                ),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: const Icon(Icons.shopping_cart_outlined, size: 28),
                  onPressed: _openCartPage,
                ),

                // Improved Badge
                if (sharedCart.isNotEmpty)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      child: Center(
                        child: Text(
                          sharedCart.length > 99
                              ? '99+'
                              : '${sharedCart.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      drawer: Drawer(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
        ),

        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),

              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white,

                    child: Icon(
                      Icons.person,
                      color: Color(0xFF667EEA),
                      size: 30,
                    ),
                  ),

                  const SizedBox(height: 14),

                  Text(
                    widget.username,

                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    widget.role.toUpperCase(),

                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),

                children: [
                  _drawerItem(
                    icon: Icons.home_rounded,
                    title: 'Home',
                    index: 0,
                  ),
                  if (widget.role == 'admin')
                    _drawerItem(
                      icon: Icons.add_box_rounded,
                      title: 'Add Product',
                      index: 2,
                    ),
                  _drawerItem(
                    icon: Icons.history_rounded,
                    title: 'History',
                    index: 6,
                  ),

                  _drawerItem(
                    icon: Icons.settings_rounded,
                    title: 'Settings',
                    index: 7,
                  ),

                  if (widget.role == 'admin')
                    _drawerItem(
                      icon: Icons.group_rounded,
                      title: 'Staff',
                      index: 5,
                    ),

                  const Divider(),

                  ListTile(
                    leading: const Icon(Icons.person),
                    title: const Text('Account'),
                    onTap: () {
                      Navigator.pop(context);
                      _openAccount();
                    },
                  ),

                  const Divider(),

                  ListTile(
                    leading: const Icon(
                      Icons.logout_rounded,
                      color: Colors.red,
                    ),

                    title: const Text(
                      'Logout',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    onTap: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          title: const Text('Logout'),
                          content: const Text(
                            'Are you sure you want to logout?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),

                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Logout'),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true && mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                          (route) => false,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: _buildPageContent(),

      bottomNavigationBar: SafeArea(
        top: false,

        child: Container(
          height: 82,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),

          padding: const EdgeInsets.symmetric(horizontal: 6),

          decoration: BoxDecoration(
            color: Colors.white,

            borderRadius: BorderRadius.circular(26),

            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),

                blurRadius: 20,

                offset: const Offset(0, 8),
              ),
            ],
          ),

          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,

            children: [
              _NavItem(
                icon: Icons.home_rounded,
                label: 'Home',
                selected: _selectedIndex == 0,
                onTap: () => _onNavBarTapped(0),
              ),

              _NavItem(
                icon: Icons.inventory_2_rounded,
                label: 'Products',
                selected: _selectedIndex == 1,
                onTap: () => _onNavBarTapped(1),
              ),

              _scannerFab(offset: const Offset(0, -18)),

              _NavItem(
                icon: Icons.point_of_sale_rounded,
                label: 'Sales',
                selected: _selectedIndex == 3,
                onTap: () => _onNavBarTapped(3),
              ),

              if (widget.role == 'admin')
                _NavItem(
                  icon: Icons.bar_chart_rounded,
                  label: 'Reports',
                  selected: _selectedIndex == 4,
                  onTap: () => _onNavBarTapped(4),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Quick Scanner Page ───────────────────────────────────────────────────────
// Lightweight scanner that captures ONE barcode and pops.
// Product lookup is handled inside SalesPage, not here.
class _QuickScannerPage extends StatefulWidget {
  final void Function(String barcode) onDetect;
  const _QuickScannerPage({required this.onDetect});

  @override
  State<_QuickScannerPage> createState() => _QuickScannerPageState();
}

class _QuickScannerPageState extends State<_QuickScannerPage> {
  bool _scanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan Product'),
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Live camera feed
          MobileScanner(
            onDetect: (capture) {
              if (_scanned) return;
              for (final barcode in capture.barcodes) {
                final code = barcode.rawValue;
                if (code != null) {
                  _scanned = true;
                  widget.onDetect(code);
                  Navigator.pop(context);
                  break;
                }
              }
            },
          ),

          // Viewfinder frame
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF667EEA), width: 2.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                children: [
                  for (final al in [
                    Alignment.topLeft,
                    Alignment.topRight,
                    Alignment.bottomLeft,
                    Alignment.bottomRight,
                  ])
                    Align(
                      alignment: al,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          border: Border(
                            top: al.y < 0
                                ? const BorderSide(
                                    color: Color(0xFF667EEA),
                                    width: 4,
                                  )
                                : BorderSide.none,
                            bottom: al.y > 0
                                ? const BorderSide(
                                    color: Color(0xFF667EEA),
                                    width: 4,
                                  )
                                : BorderSide.none,
                            left: al.x < 0
                                ? const BorderSide(
                                    color: Color(0xFF667EEA),
                                    width: 4,
                                  )
                                : BorderSide.none,
                            right: al.x > 0
                                ? const BorderSide(
                                    color: Color(0xFF667EEA),
                                    width: 4,
                                  )
                                : BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Align barcode within the frame',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Stat Pill ────────────────────────────────────────────────────────────────
class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white.withValues(alpha: 0.8), size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Nav Item ─────────────────────────────────────────────────────────────────
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = selected
        ? const Color(0xFF667EEA)
        : Colors.grey.shade500;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 62,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: selected ? 26 : 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
