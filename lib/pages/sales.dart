import 'package:flutter/material.dart';
import 'package:pos_app/utils/currency.dart';

extension<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T element) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> with TickerProviderStateMixin {
  late TabController _tabController;

  final List<Map<String, dynamic>> allProducts = [
    {
      'title': 'Twinpack Nescafe',
      'price': 8.75,
      'stock': 45,
      'imagePath': 'lib/assets/twinpack nescafe.png',
      'lowStockThreshold': 10,
    },
    {
      'title': 'Lucky Pancit Cantoon',
      'price': 24.90,
      'stock': 5,
      'imagePath': 'lib/assets/lucky pancit cantoon.png',
      'lowStockThreshold': 10,
    },
    {
      'title': 'Sardines',
      'price': 32.20,
      'stock': 0,
      'imagePath': 'lib/assets/Sardines.png',
      'lowStockThreshold': 10,
    },
    {
      'title': 'Lucky Mae',
      'price': 15.50,
      'stock': 20,
      'imagePath': 'lib/assets/lucky mae.png',
      'lowStockThreshold': 10,
    },
    {
      'title': 'Birds Tree',
      'price': 12.75,
      'stock': 8,
      'imagePath': 'lib/assets/birds tree.png',
      'lowStockThreshold': 10,
    },
  ];

  final TextEditingController searchController = TextEditingController();
  String searchQuery = '';

  List<Map<String, dynamic>> cart = [];
  List<Map<String, dynamic>> salesHistory = [
    {
      'product': 'Twinpack Nescafe',
      'date': 'May 08, 2026',
      'time': '10:23 AM',
      'quantity': 2,
      'total': 17.50,
      'status': 'Completed',
    },
    {
      'product': 'Lucky Pancit Cantoon',
      'date': 'May 08, 2026',
      'time': '9:15 AM',
      'quantity': 1,
      'total': 24.90,
      'status': 'Completed',
    },
    {
      'product': 'Sardines',
      'date': 'May 07, 2026',
      'time': '7:42 PM',
      'quantity': 3,
      'total': 96.60,
      'status': 'Completed',
    },
    {
      'product': 'Lucky Mae',
      'date': 'May 07, 2026',
      'time': '5:30 PM',
      'quantity': 2,
      'total': 31.00,
      'status': 'Completed',
    },
    {
      'product': 'Birds Tree',
      'date': 'May 06, 2026',
      'time': '4:10 PM',
      'quantity': 1,
      'total': 12.75,
      'status': 'Completed',
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    searchController.dispose();
    super.dispose();
  }

  void addToCart(Map<String, dynamic> product) {
    setState(() {
      final existingIndex = cart.indexWhere(
        (item) => item['product']['title'] == product['title'],
      );
      if (existingIndex != -1) {
        cart[existingIndex]['quantity'] += 1;
      } else {
        cart.add({'product': product, 'quantity': 1});
      }
    });
  }

  void removeFromCart(int index) {
    setState(() {
      if (cart[index]['quantity'] > 1) {
        cart[index]['quantity'] -= 1;
      } else {
        cart.removeAt(index);
      }
    });
  }

  double get cartTotal => cart.fold(
    0.0,
    (sum, item) => sum + (item['product']['price'] * item['quantity']),
  );

  int get cartQuantity =>
      cart.fold(0, (sum, item) => sum + (item['quantity'] as int));

  void openCartPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CartPage(
          cart: cart,
          onAdd: addToCart,
          onRemove: removeFromCart,
          onCompleteSale: () {
            completeSale();
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  Widget _buildCartIcon() {
    return GestureDetector(
      onTap: openCartPage,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0xFF667EEA),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shopping_cart_outlined,
              color: Colors.white,
              size: 24,
            ),
          ),
          if (cartQuantity > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$cartQuantity',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> get filteredProducts {
    if (searchQuery.isEmpty) return allProducts;
    return allProducts.where((product) {
      final title = (product['title'] as String).toLowerCase();
      return title.contains(searchQuery.toLowerCase());
    }).toList();
  }

  void completeSale() {
    if (cart.isEmpty) return;

    final now = DateTime.now();
    final date =
        '${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}/${now.year}';
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final time =
        '${hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}';

    for (final item in cart) {
      salesHistory.insert(0, {
        'product': item['product']['title'],
        'date': date,
        'time': time,
        'quantity': item['quantity'],
        'total': item['product']['price'] * item['quantity'],
        'status': 'Completed',
      });
    }

    setState(() {
      cart.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sale completed successfully!')),
    );
  }

  Widget _qtyButton({
    required IconData icon,
    required VoidCallback onTap,
    required Color bgColor,
    required Color iconColor,
    double size = 40,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: iconColor),
      ),
    );
  }

  Color _getStockColor(int stock) {
    if (stock == 0) return Colors.red;
    if (stock <= 10) return Colors.orange;
    return Colors.green;
  }

  String _getStockStatus(int stock) {
    if (stock == 0) return 'Out of Stock';
    if (stock <= 10) return 'Low Stock';
    return 'In Stock';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 20.0,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Sales',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Create new sales or view transaction history.',
                          style: TextStyle(fontSize: 14, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  _buildCartIcon(),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'New Sale'),
                Tab(text: 'History'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // ── NEW SALE TAB ──────────────────────────────────
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 10.0,
                        ),
                        child: TextField(
                          controller: searchController,
                          decoration: InputDecoration(
                            hintText: 'Search products',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      searchController.clear();
                                      setState(() {
                                        searchQuery = '';
                                      });
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14.0),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onChanged: (value) {
                            setState(() {
                              searchQuery = value;
                            });
                          },
                        ),
                      ),
                      // Product list — takes remaining space above cart
                      Expanded(
                        child: filteredProducts.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.search_off,
                                      size: 64,
                                      color: Colors.grey[300],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No products found',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(16.0),
                                itemCount: filteredProducts.length,
                                itemBuilder: (context, index) {
                                  final product = filteredProducts[index];
                                  final stockColor = _getStockColor(
                                    product['stock'],
                                  );
                                  final stockStatus = _getStockStatus(
                                    product['stock'],
                                  );
                                  final isOutOfStock = product['stock'] == 0;
                                  final cartItem = cart.firstWhereOrNull(
                                    (item) =>
                                        item['product']['title'] ==
                                        product['title'],
                                  );
                                  final qty = cartItem?['quantity'] ?? 0;

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 14.0),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18.0),
                                    ),
                                    elevation: 2,
                                    child: Padding(
                                      padding: const EdgeInsets.all(14.0),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(12.0),
                                                child: Image.asset(
                                                  product['imagePath'],
                                                  width: 70,
                                                  height: 70,
                                                  fit: BoxFit.cover,
                                                  errorBuilder:
                                                      (
                                                        context,
                                                        error,
                                                        stackTrace,
                                                      ) => Container(
                                                        width: 70,
                                                        height: 70,
                                                        color: Colors.grey[200],
                                                        child: const Icon(
                                                          Icons.image,
                                                          color: Colors.grey,
                                                        ),
                                                      ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      product['title'],
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 15,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      CurrencyFormatter.format(
                                                        product['price'],
                                                      ),
                                                      style: const TextStyle(
                                                        fontSize: 15,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: Color(
                                                          0xFF667EEA,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8.0,
                                                            vertical: 4.0,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: stockColor
                                                            .withValues(
                                                              alpha: 0.15,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              6.0,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        '$stockStatus (${product['stock']})',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: stockColor,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          if (isOutOfStock)
                                            Container(
                                              width: double.infinity,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 10,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.red.withValues(
                                                  alpha: 0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: const Text(
                                                'Out of Stock',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: Colors.red,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            )
                                          else if (qty == 0)
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.end,
                                              children: [
                                                _qtyButton(
                                                  icon: Icons.add,
                                                  bgColor: const Color(
                                                    0xFF667EEA,
                                                  ),
                                                  iconColor: Colors.white,
                                                  size: 36,
                                                  onTap: () =>
                                                      addToCart(product),
                                                ),
                                              ],
                                            )
                                          else
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  'In cart: $qty',
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                _qtyButton(
                                                  icon: Icons.add,
                                                  bgColor: const Color(
                                                    0xFF667EEA,
                                                  ),
                                                  iconColor: Colors.white,
                                                  size: 36,
                                                  onTap: () =>
                                                      addToCart(product),
                                                ),
                                              ],
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),

                  // ── HISTORY TAB ───────────────────────────────────
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(16.0),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18.0),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.04,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Total Sales',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      CurrencyFormatter.format(
                                        salesHistory.fold(
                                          0.0,
                                          (sum, item) =>
                                              sum + (item['total'] as double),
                                        ),
                                      ),
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(16.0),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18.0),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.04,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Orders',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${salesHistory.length}',
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          itemCount: salesHistory.length,
                          itemBuilder: (context, index) {
                            final entry = salesHistory[index];
                            final statusColor = entry['status'] == 'Completed'
                                ? Colors.green
                                : Colors.orange;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 14.0),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18.0),
                              ),
                              elevation: 1,
                              child: Padding(
                                padding: const EdgeInsets.all(14.0),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                entry['product'] as String,
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                '${entry['date']} • ${entry['time']}',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.black54,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              'Qty: ${entry['quantity']}',
                                              style: const TextStyle(
                                                fontSize: 14,
                                                color: Colors.black54,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              CurrencyFormatter.format(
                                                entry['total'] as double,
                                              ),
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8.0,
                                        vertical: 4.0,
                                      ),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          8.0,
                                        ),
                                      ),
                                      child: Text(
                                        entry['status'] as String,
                                        style: TextStyle(
                                          color: statusColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
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

class CartPage extends StatefulWidget {
  const CartPage({
    super.key,
    required this.cart,
    required this.onAdd,
    required this.onRemove,
    required this.onCompleteSale,
  });

  final List<Map<String, dynamic>> cart;
  final void Function(Map<String, dynamic> product) onAdd;
  final void Function(int index) onRemove;
  final VoidCallback onCompleteSale;

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  @override
  Widget build(BuildContext context) {
    final cart = widget.cart;
    final double cartTotal = cart.fold(
      0.0,
      (sum, item) => sum + (item['product']['price'] * item['quantity']),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Shopping Cart'), centerTitle: true),
      body: cart.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(
                    Icons.shopping_cart_outlined,
                    size: 72,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Your cart is empty',
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      itemCount: cart.length,
                      itemBuilder: (context, i) {
                        final item = cart[i];
                        final String name = item['product']['title'];
                        final double price = item['product']['price'];
                        final int qty = item['quantity'];
                        final double subtotal = price * qty;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14.0),
                          child: Container(
                            padding: const EdgeInsets.all(14.0),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18.0),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () =>
                                          setState(() => widget.onRemove(i)),
                                      child: Icon(
                                        Icons.delete_outline,
                                        color: Colors.red[400],
                                        size: 22,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Price',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            CurrencyFormatter.format(price),
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF667EEA),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          GestureDetector(
                                            onTap: () => setState(
                                              () => widget.onRemove(i),
                                            ),
                                            child: Container(
                                              width: 32,
                                              height: 32,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                color: Colors.grey[200],
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: const Icon(
                                                Icons.remove,
                                                color: Colors.black87,
                                                size: 20,
                                              ),
                                            ),
                                          ),
                                          SizedBox(
                                            width: 40,
                                            child: Text(
                                              '$qty',
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () => setState(
                                              () =>
                                                  widget.onAdd(item['product']),
                                            ),
                                            child: Container(
                                              width: 32,
                                              height: 32,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF667EEA),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: const Icon(
                                                Icons.add,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            'Subtotal',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            CurrencyFormatter.format(subtotal),
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 14.0,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Colors.grey[200]!, width: 1),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total:',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          CurrencyFormatter.format(cartTotal),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF667EEA),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: widget.onCompleteSale,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF667EEA),
                        minimumSize: const Size(double.infinity, 56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Complete Sale',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
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
