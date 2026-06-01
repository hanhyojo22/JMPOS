import 'dart:async';
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
import 'edit_product_page.dart';
import 'setting_page.dart';
import 'login.dart';
import 'shop_cart_page.dart' as shop_cart;
import 'package:pos_app/utils/message_banner.dart';
import 'package:pos_app/widgets/barcode_scanner_viewport.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.title,
    required this.username,
    required this.role,
    this.readOnly = false,
    this.initialSuccessMessage,
  });

  final String username;
  final String title;
  final String role;
  final bool readOnly;
  final String? initialSuccessMessage;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey _cartIconKey = GlobalKey();
  final List<Map<String, dynamic>> sharedCart = [];
  String? addProductScannedBarcode;
  int _selectedIndex = 0;
  String? salesScannedBarcode;
  final int _salesBarcodeScanVersion = 0;
  String? productsScannedBarcode;
  String? addProductBarcode;
  String? editProductBarcode;
  bool _barcodeScannerEnabled = true;
  Map<String, dynamic>? selectedProduct;
  double totalSales = 0;
  int totalTransactions = 0;
  double yesterdaySales = 0;
  List<Map<String, dynamic>> recentTransactions = [];
  bool _loadingHome = true;
  String? _topMessage;
  bool _topMessageSuccess = false;
  String? _currentUserDisplayName;
  int _cartPulseVersion = 0;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  bool get _isStaff => widget.role.toLowerCase() == 'staff';
  Color get _pageSurface =>
      _isDark ? const Color(0xFF0F172A) : const Color(0xFFF4F5FF);
  Color get _panelSurface => _isDark ? const Color(0xFF111827) : Colors.white;
  Color get _primaryText => _isDark ? const Color(0xFFF8FAFC) : Colors.black87;
  Color get _secondaryText =>
      _isDark ? const Color(0xFFCBD5E1) : Colors.grey.shade500;
  Color get _softShadow => _isDark
      ? Colors.black.withValues(alpha: 0.22)
      : Colors.black.withValues(alpha: 0.04);
  double get _todayVsYesterdayPercent {
    if (yesterdaySales <= 0) {
      return totalSales > 0 ? 100 : 0;
    }
    return ((totalSales - yesterdaySales) / yesterdaySales) * 100;
  }

  String get _todayVsYesterdayLabel {
    final percent = _todayVsYesterdayPercent;
    final sign = percent > 0 ? '+' : '';
    final rounded = percent.abs() >= 10
        ? percent.toStringAsFixed(0)
        : percent.toStringAsFixed(1);
    return '$sign$rounded%';
  }

  int get _sharedCartItemCount => sharedCart.fold(
    0,
    (total, item) => total + ((item['quantity'] as num?)?.toInt() ?? 0),
  );

  Offset? _cartIconCenter() {
    final renderObject = _cartIconKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    return renderObject.localToGlobal(renderObject.size.center(Offset.zero));
  }

  void _pulseCartIcon() {
    if (!mounted) return;
    setState(() => _cartPulseVersion++);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadCurrentUserDisplayName());
    loadRecentTransactions();
    final initialSuccessMessage = widget.initialSuccessMessage?.trim();
    if (initialSuccessMessage?.isNotEmpty == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showTopMessage(initialSuccessMessage!, success: true);
      });
    }
  }

  Future<void> _loadCurrentUserDisplayName() async {
    final user = await DatabaseHelper.instance.getUserByUsername(
      widget.username,
    );
    if (!mounted) return;
    setState(() {
      _currentUserDisplayName =
          user?['full_name']?.toString().trim().isNotEmpty == true
          ? user!['full_name'].toString().trim()
          : _fallbackDisplayName(widget.username);
    });
  }

  String _fallbackDisplayName(String username) {
    final normalized = username.trim();
    final generatedStaffName = RegExp(
      r'^staff_\d+_(.+)$',
    ).firstMatch(normalized);
    if (generatedStaffName != null) {
      return generatedStaffName
          .group(1)!
          .split('_')
          .where((part) => part.isNotEmpty)
          .map((part) => part[0].toUpperCase() + part.substring(1))
          .join(' ');
    }
    return normalized;
  }

  Future<void> loadRecentTransactions() async {
    setState(() => _loadingHome = true);
    try {
      final db = await DatabaseHelper.instance.database;
      await DatabaseHelper.instance.ensureSalesSchema();
      if (!widget.readOnly) {
        await DatabaseHelper.instance.completeDueSales();
      }

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1));
      final yesterdayStart = todayStart.subtract(const Duration(days: 1));

      final totalResult = await db.rawQuery(
        '''
        SELECT
          COALESCE(SUM(total), 0)  AS grand_total,
          COUNT(
            DISTINCT COALESCE(
              NULLIF(receipt_number, ''),
              substr(created_at, 1, 19)
            )
          ) AS total_count
        FROM sales
        WHERE created_at >= ? AND created_at < ?
          AND (voided_at IS NULL OR voided_at = '')
      ''',
        [todayStart.toIso8601String(), todayEnd.toIso8601String()],
      );

      final yesterdayResult = await db.rawQuery(
        '''
        SELECT COALESCE(SUM(total), 0) AS yesterday_total
        FROM sales
        WHERE created_at >= ? AND created_at < ?
          AND (voided_at IS NULL OR voided_at = '')
      ''',
        [yesterdayStart.toIso8601String(), todayStart.toIso8601String()],
      );

      final transactions = await db.rawQuery('''
        SELECT
          MIN(sales.id) AS id,
          COALESCE(
            NULLIF(sales.receipt_number, ''),
            'R-' || MIN(sales.id)
          ) AS receipt_number,
          GROUP_CONCAT(sales.product_name, ', ') AS product_name,
          SUM(sales.total) AS total,
          SUM(sales.quantity) AS quantity,
          MIN(sales.created_at) AS created_at
        FROM sales
        LEFT JOIN products ON sales.product_id = products.id
        WHERE sales.voided_at IS NULL OR sales.voided_at = ''
        GROUP BY COALESCE(
          NULLIF(sales.receipt_number, ''),
          substr(sales.created_at, 1, 19)
        )
        ORDER BY MAX(sales.created_at) DESC, MAX(sales.id) DESC
        LIMIT 4
      ''');

      final double salesTotal =
          (totalResult.first['grand_total'] as num?)?.toDouble() ?? 0.0;
      final int transactionCount =
          (totalResult.first['total_count'] as num?)?.toInt() ?? 0;
      final double salesYesterday =
          (yesterdayResult.first['yesterday_total'] as num?)?.toDouble() ?? 0.0;

      setState(() {
        totalSales = salesTotal;
        totalTransactions = transactionCount;
        yesterdaySales = salesYesterday;

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

          final receiptNumber = sale['receipt_number']?.toString().trim();

          return {
            'id': sale['id'],
            'title': receiptNumber != null && receiptNumber.isNotEmpty
                ? receiptNumber
                : 'Sale #${sale['id']}',
            'subtitle': subtitle,
            'amount': (sale['total'] as num?)?.toDouble() ?? 0.0,
            'quantity': sale['quantity'] ?? 0,
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
    if (_isStaff) return;
    setState(() => _selectedIndex = 10);
  }

  Widget _buildAccessDeniedPage() {
    return Center(
      child: Text(
        'Access denied',
        style: TextStyle(
          color: _secondaryText,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ── Step 1: open scanner  Step 2: if barcode captured → open SalesPage ──────
  Future<void> _openScannerAction() async {
    if (!_barcodeScannerEnabled) {
      _showSnack('Barcode scanner is disabled in Settings', isError: true);
      return;
    }

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
    if (_selectedIndex == 1 && !_isStaff) {
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
        editProductBarcode = scannedBarcode;
      });

      return;
    }

    final productName = await _addScannedBarcodeToSharedCart(scannedBarcode!);
    if (!mounted || productName == null) return;

    await _openCartPage(initialMessage: '$productName added to cart');
  }

  void _showSnack(String message, {bool isError = false, bool top = false}) {
    if (!mounted) return;
    if (top) {
      _showTopMessage(message, success: !isError);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showTopMessage(String message, {bool success = false}) {
    setState(() {
      _topMessage = message;
      _topMessageSuccess = success;
    });

    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted || _topMessage != message) return;
      setState(() => _topMessage = null);
    });
  }

  Future<String?> _addScannedBarcodeToSharedCart(String barcode) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'products',
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );

    if (!mounted) return null;

    if (rows.isEmpty) {
      _showSnack('Product not found', isError: true, top: true);
      return null;
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
        return null;
      }

      setState(() {
        cartProduct['stock'] = stock - 1;
        sharedCart[cartIndex]['quantity'] += 1;
      });
    } else {
      final stock = (productRow['stock_quantity'] as num?)?.toInt() ?? 0;

      if (stock <= 0) {
        _showSnack('$productName is out of stock', isError: true);
        return null;
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
    return productName;
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

  Future<String?> _refreshSharedCart() async {
    if (sharedCart.isEmpty) return null;

    final db = await DatabaseHelper.instance.database;
    final refreshedCart = <Map<String, dynamic>>[];
    var removedCount = 0;
    var adjustedCount = 0;

    for (final item in sharedCart) {
      final product = item['product'];
      if (product is! Map) {
        removedCount++;
        continue;
      }

      final productId = (product['id'] as num?)?.toInt();
      final quantity = (item['quantity'] as num?)?.toInt() ?? 0;

      if (productId == null || quantity <= 0) {
        removedCount++;
        continue;
      }

      final rows = await db.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );

      if (rows.isEmpty) {
        removedCount++;
        continue;
      }

      final row = rows.first;
      final dbStock = (row['stock_quantity'] as num?)?.toInt() ?? 0;
      final refreshedQuantity = quantity > dbStock ? dbStock : quantity;

      if (refreshedQuantity <= 0) {
        removedCount++;
        continue;
      }

      if (refreshedQuantity != quantity) {
        adjustedCount++;
      }

      refreshedCart.add({
        'product': {
          'id': productId,
          'title': row['product_name']?.toString() ?? 'Product',
          'price': row['price'],
          'stock': dbStock - refreshedQuantity,
          'barcode': row['barcode'] ?? '',
          'imagePath': row['image_url'] ?? '',
          'category': row['category'] ?? 'Other',
        },
        'quantity': refreshedQuantity,
      });
    }

    if (!mounted) return null;

    setState(() {
      sharedCart
        ..clear()
        ..addAll(refreshedCart);
    });

    if (removedCount > 0 && adjustedCount > 0) {
      return 'Cart refreshed. Removed unavailable items and adjusted stock.';
    }
    if (removedCount > 0) {
      return removedCount == 1
          ? 'Cart refreshed. Removed 1 unavailable item.'
          : 'Cart refreshed. Removed $removedCount unavailable items.';
    }
    if (adjustedCount > 0) {
      return adjustedCount == 1
          ? 'Cart refreshed. Adjusted 1 item to current stock.'
          : 'Cart refreshed. Adjusted $adjustedCount items to current stock.';
    }

    return null;
  }

  Future<shop_cart.SaleCompletion?> _completeSharedSale() async {
    if (sharedCart.isEmpty) return null;

    final db = await DatabaseHelper.instance.database;
    try {
      await DatabaseHelper.instance.ensureSalesSchema();
      final createdAt = DateTime.now();
      final completionDueAt = createdAt.add(
        DatabaseHelper.saleCompletionGracePeriod,
      );
      final receiptNumber = DatabaseHelper.instance.generateReceiptNumber(
        createdAt,
      );
      int? firstSaleId;
      await db.transaction((txn) async {
        for (final item in sharedCart) {
          final product = item['product'] as Map<String, dynamic>;
          final productId = (product['id'] as num?)?.toInt();
          final productName = product['title']?.toString() ?? 'Product';
          final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
          final localRemainingStock = (product['stock'] as num?)?.toInt() ?? 0;

          if (productId == null || quantity <= 0) {
            throw Exception('Invalid cart item: $productName');
          }

          final currentRows = await txn.query(
            'products',
            columns: ['id', 'stock_quantity'],
            where: 'id = ?',
            whereArgs: [productId],
            limit: 1,
          );

          if (currentRows.isEmpty) {
            throw Exception('$productName was deleted. Remove it from cart.');
          }

          final dbStock =
              (currentRows.first['stock_quantity'] as num?)?.toInt() ?? 0;
          final expectedStock = localRemainingStock + quantity;

          if (dbStock != expectedStock) {
            throw Exception(
              '$productName stock changed. Refresh cart before checkout.',
            );
          }

          if (dbStock < quantity) {
            throw Exception('$productName does not have enough stock.');
          }

          final price = (product['price'] as num).toDouble();
          final imagePath = product['imagePath']?.toString();
          final remainingStock = dbStock - quantity;

          final saleRow = {
            'product_id': productId,
            'product_name': productName,
            'quantity': quantity,
            'price': price,
            'total': price * quantity,
            'image_url': imagePath == null || imagePath.isEmpty
                ? null
                : imagePath,
            'completion_due_at': completionDueAt.toIso8601String(),
            'completed_at': null,
            'receipt_number': receiptNumber,
            'created_at': createdAt.toIso8601String(),
          };
          final saleId = await txn.insert('sales', saleRow);
          firstSaleId ??= saleId;
          await DatabaseHelper.instance.queueSyncUpsert('sales', {
            ...saleRow,
            'id': saleId,
          }, executor: txn);

          await txn.update(
            'products',
            {
              'stock_quantity': remainingStock,
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [productId],
          );
          final updatedProductRows = await txn.query(
            'products',
            where: 'id = ?',
            whereArgs: [productId],
            limit: 1,
          );
          if (updatedProductRows.isNotEmpty) {
            await DatabaseHelper.instance.queueSyncUpsert(
              'products',
              updatedProductRows.first,
              executor: txn,
            );
          }

          product['stock'] = remainingStock;
        }
      });
      unawaited(DatabaseHelper.instance.syncPendingChanges());

      sharedCart.clear();
      Timer(DatabaseHelper.saleCompletionGracePeriod, () async {
        await DatabaseHelper.instance.completeDueSales();
      });
      await loadRecentTransactions();
      return firstSaleId == null
          ? null
          : shop_cart.SaleCompletion(
              saleId: firstSaleId!,
              receiptNumber: receiptNumber,
            );
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      _showSnack(message, isError: true, top: true);
      return null;
    }
  }

  Future<void> _openCartPage({String? initialMessage}) async {
    final refreshMessage = await _refreshSharedCart();
    if (!mounted) return;

    setState(() => _selectedIndex = 9);
    final message = refreshMessage ?? initialMessage;
    if (message != null && message.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _selectedIndex != 9) return;
        _showTopMessage(message, success: true);
      });
    }
  }

  Widget _buildPageContent() {
    if (widget.readOnly && !{0, 4, 6}.contains(_selectedIndex)) {
      return _buildAccessDeniedPage();
    }
    switch (_selectedIndex) {
      case 1:
        if (_isStaff) {
          return SalesPage(
            cart: sharedCart,
            currentUsername: widget.username,
            cartTargetGlobalPosition: _cartIconCenter,
            onCartAnimationArrived: _pulseCartIcon,
            onCartChanged: () {
              if (mounted) setState(() {});
            },
          );
        }

        return ProductsPage(
          scannedBarcode: productsScannedBarcode,
          cart: sharedCart,
          currentUsername: widget.username,
          onCartChanged: () {
            if (mounted) setState(() {});
          },
          onBarcodeHandled: () {
            productsScannedBarcode = null;
          },
          onAddProduct: () {
            setState(() => _selectedIndex = 2);
          },

          onEditProduct: (product) {
            setState(() {
              selectedProduct = product;
              _selectedIndex = 8;
            });
          },
        );

      case 2:
        return AddProductsPage(
          initialBarcode: addProductBarcode,
          currentUsername: widget.username,
          onBarcodeHandled: () {
            addProductBarcode = null;
          },
          onBack: () {
            _scaffoldKey.currentState?.openDrawer();
          },
        );

      case 3:
        return SalesPage(
          key: ValueKey(
            '${salesScannedBarcode ?? 'sales'}_$_salesBarcodeScanVersion',
          ),

          cart: sharedCart,
          currentUsername: widget.username,
          cartTargetGlobalPosition: _cartIconCenter,
          onCartAnimationArrived: _pulseCartIcon,
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
          return ReportsPage(
            onOpenMenu: () => _scaffoldKey.currentState?.openDrawer(),
            readOnly: widget.readOnly,
          );
        }
        return SalesPage(
          cart: sharedCart,
          currentUsername: widget.username,
          cartTargetGlobalPosition: _cartIconCenter,
          onCartAnimationArrived: _pulseCartIcon,
          onCartChanged: () {
            if (mounted) setState(() {});
          },
        );

      case 5:
        if (widget.role == 'admin') {
          return StaffManagementPage(currentUsername: widget.username);
        }
        break;

      case 6:
        return HistoryPage(
          currentUsername: widget.username,
          readOnly: widget.readOnly,
        );

      case 7:
        return SettingsPage(
          currentUsername: widget.username,
          barcodeScannerEnabled: _barcodeScannerEnabled,
          onBarcodeScannerChanged: (enabled) {
            if (mounted) {
              setState(() => _barcodeScannerEnabled = enabled);
            }
          },
        );
      case 8:
        if (_isStaff) {
          return SalesPage(
            cart: sharedCart,
            currentUsername: widget.username,
            cartTargetGlobalPosition: _cartIconCenter,
            onCartAnimationArrived: _pulseCartIcon,
            onCartChanged: () {
              if (mounted) setState(() {});
            },
          );
        }

        if (selectedProduct == null) {
          return const Center(child: Text('No product selected'));
        }

        return EditProductPage(
          key: ValueKey(selectedProduct!['id']),

          product: selectedProduct!,
          scannedBarcode: editProductBarcode,
          currentUsername: widget.username,
          onBarcodeHandled: () {
            editProductBarcode = null;
          },

          onSaved: () {
            setState(() {
              productsScannedBarcode = null;
              editProductBarcode = null;
              _selectedIndex = 1;
            });
          },
        );

      case 9:
        return shop_cart.CartPage(
          cart: sharedCart,
          showAppBar: false,
          onCartChanged: () {
            if (mounted) setState(() {});
          },
          onAdd: _addToSharedCart,
          onRemove: _removeFromSharedCart,
          onDelete: _deleteFromSharedCart,
          currentUsername: widget.username,
          onCompleteSale: () async {
            return _completeSharedSale();
          },
          onBrowseProducts: () {
            setState(() => _selectedIndex = 3);
          },
        );

      case 10:
        if (_isStaff) return _buildAccessDeniedPage();
        return AccountPage(username: widget.username);
    }

    // ── Home tab ─────────────────────────────────────────────────────────────
    return RefreshIndicator(
      onRefresh: loadRecentTransactions,
      child: ColoredBox(
        color: _pageSurface,
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
                                      color: Colors.white.withValues(
                                        alpha: 0.75,
                                      ),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 106,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _todayVsYesterdayPercent < 0
                                          ? Icons.trending_down
                                          : Icons.trending_up,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          _todayVsYesterdayLabel,
                                          maxLines: 1,
                                          softWrap: false,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text(
                            CurrencyFormatter.format(totalSales),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
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
                                  icon: Icons.history_rounded,
                                  label: 'Yesterday Sales',
                                  value: CurrencyFormatter.format(
                                    yesterdaySales,
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
                    Text(
                      'Recent Transactions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _primaryText,
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _selectedIndex = 6),
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
                          style: TextStyle(fontSize: 14, color: _secondaryText),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Completed sales will appear here',
                          style: TextStyle(
                            fontSize: 12,
                            color: _secondaryText.withValues(alpha: 0.72),
                          ),
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
                          color: _panelSurface,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: _softShadow,
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
                          title: Text(
                            t['title'] as String,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _primaryText,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            t['subtitle'] as String,
                            style: TextStyle(
                              fontSize: 12,
                              color: _secondaryText,
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
                                  color: _secondaryText.withValues(alpha: 0.7),
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
      ),
    );
  }

  void _onNavBarTapped(int index) async {
    if (widget.readOnly && !{0, 4, 6}.contains(index)) return;
    if (_isStaff && index == 1) return;

    setState(() => _selectedIndex = index);
    if (index == 0) await loadRecentTransactions();
  }

  Widget _drawerItem({
    required IconData icon,
    required String title,
    required int index,
  }) {
    final bool active = _selectedIndex == index;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color inactiveIcon = isDark ? const Color(0xFF94A3B8) : Colors.grey;
    final Color inactiveText = isDark
        ? const Color(0xFFE2E8F0)
        : Colors.black87;

    return ListTile(
      leading: Icon(
        icon,
        color: active ? const Color(0xFF667EEA) : inactiveIcon,
      ),

      title: Text(
        title,

        style: TextStyle(
          fontWeight: active ? FontWeight.bold : FontWeight.w500,

          color: active ? const Color(0xFF667EEA) : inactiveText,
        ),
      ),

      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),

      selected: active,
      selectedTileColor: const Color(0xFF667EEA).withValues(alpha: 0.12),

      onTap: () {
        if (widget.readOnly && !{0, 4, 6}.contains(index)) return;
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

  Widget _scannerFab({Offset offset = Offset.zero}) {
    final enabled = _barcodeScannerEnabled;

    return GestureDetector(
      onTap: enabled ? _openScannerAction : null,
      child: Transform.translate(
        offset: offset,
        child: Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: enabled
                  ? const [Color(0xFF667EEA), Color(0xFF764BA2)]
                  : const [Color(0xFFCBD5E1), Color(0xFF94A3B8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (enabled ? const Color(0xFF667EEA) : Colors.black)
                    .withValues(alpha: enabled ? 0.45 : 0.14),
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
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color drawerSurface = isDark ? const Color(0xFF111827) : Colors.white;
    final Color drawerText = isDark ? const Color(0xFFE2E8F0) : Colors.black87;
    final Color drawerIcon = isDark
        ? const Color(0xFF94A3B8)
        : Colors.grey.shade700;
    final Color drawerDivider = isDark
        ? const Color(0xFF253047)
        : Colors.grey.shade300;

    return Scaffold(
      key: _scaffoldKey,
      appBar: {2, 4, 9}.contains(_selectedIndex)
          ? null
          : AppBar(
              leadingWidth: 44,
              titleSpacing: 0,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
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
                if (!widget.readOnly)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        TweenAnimationBuilder<double>(
                          key: ValueKey(_cartPulseVersion),
                          tween: Tween(begin: 0.82, end: 1),
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.elasticOut,
                          builder: (context, scale, child) =>
                              Transform.scale(scale: scale, child: child),
                          child: IconButton(
                            key: _cartIconKey,
                            icon: const Icon(
                              Icons.shopping_cart_outlined,
                              size: 28,
                            ),
                            onPressed: _openCartPage,
                          ),
                        ),

                        // Improved Badge
                        if (_sharedCartItemCount > 0)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 20,
                                minHeight: 20,
                              ),
                              child: Center(
                                child: Text(
                                  _sharedCartItemCount > 99
                                      ? '99+'
                                      : '$_sharedCartItemCount',
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
        backgroundColor: drawerSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
        ),

        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),

              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),

              child: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.white,

                      child: const Icon(
                        Icons.person,
                        color: Color(0xFF667EEA),
                        size: 30,
                      ),
                    ),

                    const SizedBox(height: 14),

                    Text(
                      _currentUserDisplayName ??
                          _fallbackDisplayName(widget.username),

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
                  if (widget.role == 'admin' && !widget.readOnly)
                    _drawerItem(
                      icon: Icons.add_box_rounded,
                      title: 'Add Product',
                      index: 2,
                    ),
                  _drawerItem(
                    icon: Icons.receipt_long_rounded,
                    title: 'Sales History',
                    index: 6,
                  ),

                  if (!widget.readOnly)
                    _drawerItem(
                      icon: Icons.settings_rounded,
                      title: 'Settings',
                      index: 7,
                    ),

                  if (widget.role == 'admin' && !widget.readOnly)
                    _drawerItem(
                      icon: Icons.group_rounded,
                      title: 'Staff',
                      index: 5,
                    ),

                  Divider(color: drawerDivider),

                  if (!_isStaff && !widget.readOnly)
                    ListTile(
                      leading: Icon(Icons.person, color: drawerIcon),
                      title: Text(
                        'Account',
                        style: TextStyle(
                          color: drawerText,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _openAccount();
                      },
                    ),

                  Divider(color: drawerDivider),

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
                          backgroundColor: drawerSurface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          title: Text(
                            'Logout',
                            style: TextStyle(color: drawerText),
                          ),
                          content: Text(
                            'Are you sure you want to logout?',
                            style: TextStyle(
                              color: isDark
                                  ? const Color(0xFFCBD5E1)
                                  : Colors.black87,
                            ),
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

                      if (!context.mounted) return;

                      if (confirm == true) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (_) =>
                                LoginPage(readOnly: widget.readOnly),
                          ),
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
      body: Stack(
        children: [
          _buildPageContent(),
          if (widget.readOnly)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Material(
                  color: Color(0xFFB91C1C),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      'License expired: read-only mode',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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

      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 82,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: drawerSurface,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.28)
                    : Colors.black.withValues(alpha: 0.08),
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

              if (!widget.readOnly && !_isStaff)
                _NavItem(
                  icon: Icons.inventory_2_rounded,
                  label: 'Products',
                  selected: _selectedIndex == 1,
                  onTap: () => _onNavBarTapped(1),
                ),

              if (!widget.readOnly) _scannerFab(offset: const Offset(0, -18)),

              if (!widget.readOnly)
                _NavItem(
                  icon: Icons.point_of_sale_rounded,
                  label: 'Sales',
                  selected: _selectedIndex == 3,
                  onTap: () => _onNavBarTapped(3),
                ),

              if (widget.readOnly)
                _NavItem(
                  icon: Icons.receipt_long_rounded,
                  label: 'History',
                  selected: _selectedIndex == 6,
                  onTap: () => _onNavBarTapped(6),
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
      body: BarcodeScannerViewport(
        onDetect: (code) {
          widget.onDetect(code);
          Navigator.pop(context);
        },
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
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
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
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color color = selected
        ? const Color(0xFF667EEA)
        : isDark
        ? const Color(0xFFCBD5E1)
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
