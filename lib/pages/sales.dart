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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sales',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Create new sales or view transaction history.',
                    style: TextStyle(fontSize: 14, color: Colors.black54),
                  ),
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
                      Expanded(
                        child: allProducts.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.shopping_bag_outlined,
                                      size: 64,
                                      color: Colors.grey[300],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No products available',
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
                                itemCount: allProducts.length,
                                itemBuilder: (context, index) {
                                  final product = allProducts[index];
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
                                                  size: 36, // smaller size
                                                  onTap: () =>
                                                      addToCart(product),
                                                ),
                                              ],
                                            )
                                          else
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                _qtyButton(
                                                  icon: Icons.remove,
                                                  bgColor: Colors.grey[200]!,
                                                  iconColor: Colors.black87,
                                                  onTap: () {
                                                    final cartIndex = cart
                                                        .indexWhere(
                                                          (item) =>
                                                              item['product']['title'] ==
                                                              product['title'],
                                                        );
                                                    if (cartIndex != -1) {
                                                      removeFromCart(cartIndex);
                                                    }
                                                  },
                                                ),
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 16,
                                                      ),
                                                  child: Text(
                                                    '$qty',
                                                    style: const TextStyle(
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                _qtyButton(
                                                  icon: Icons.add,
                                                  bgColor: const Color(
                                                    0xFF667EEA,
                                                  ),
                                                  iconColor: Colors.white,
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

                      // Cart panel
                      if (cart.isNotEmpty)
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border(
                              top: BorderSide(
                                color: Colors.grey[200]!,
                                width: 2,
                              ),
                            ),
                          ),
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Shopping Cart',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF667EEA),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${cart.length} item${cart.length != 1 ? 's' : ''}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              ...List.generate(cart.length, (i) {
                                final item = cart[i];
                                final String name = item['product']['title'];
                                final double price = item['product']['price'];
                                final int qty = item['quantity'];
                                final double subtotal = price * qty;

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[50],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.grey[200]!,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                name,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  cart.removeAt(i);
                                                });
                                              },
                                              child: Icon(
                                                Icons.delete_outline,
                                                color: Colors.red[400],
                                                size: 20,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            // Price
                                            Expanded(
                                              flex: 2,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Price',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                  Text(
                                                    CurrencyFormatter.format(
                                                      price,
                                                    ),
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Color(0xFF667EEA),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Qty stepper
                                            Expanded(
                                              flex: 2,
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  _qtyButton(
                                                    icon: Icons.remove,
                                                    bgColor: Colors.grey[200]!,
                                                    iconColor: Colors.black87,
                                                    size: 36,
                                                    onTap: () =>
                                                        removeFromCart(i),
                                                  ),
                                                  SizedBox(
                                                    width: 40,
                                                    child: Text(
                                                      '$qty',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: const TextStyle(
                                                        fontSize: 15,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                  _qtyButton(
                                                    icon: Icons.add,
                                                    bgColor: const Color(
                                                      0xFF667EEA,
                                                    ),
                                                    iconColor: Colors.white,
                                                    size: 36,
                                                    onTap: () => addToCart(
                                                      item['product'],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Subtotal
                                            Expanded(
                                              flex: 2,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    'Subtotal',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                  Text(
                                                    CurrencyFormatter.format(
                                                      subtotal,
                                                    ),
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.bold,
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
                              }),

                              Divider(height: 24, color: Colors.grey[300]),

                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
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
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF667EEA),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              ElevatedButton(
                                onPressed: completeSale,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF667EEA),
                                  minimumSize: const Size(double.infinity, 56),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 2,
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Complete Sale',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
