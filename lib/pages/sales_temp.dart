import 'package:flutter/material.dart';
import 'package:pos_app/utils/currency.dart';

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
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}';

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
                  // New Sale Tab
                  Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16.0),
                          itemCount: allProducts.length,
                          itemBuilder: (context, index) {
                            final product = allProducts[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12.0),
                              child: ListTile(
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(8.0),
                                  child: Image.asset(
                                    product['imagePath'],
                                    width: 50,
                                    height: 50,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Icon(Icons.image),
                                  ),
                                ),
                                title: Text(product['title']),
                                subtitle: Text(
                                  CurrencyFormatter.format(product['price']),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.add),
                                  onPressed: () => addToCart(product),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      if (cart.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(16.0),
                          color: Colors.white,
                          child: Column(
                            children: [
                              const Text(
                                'Cart',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...cart.map(
                                (item) => Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${item['product']['title']} x${item['quantity']}',
                                    ),
                                    Row(
                                      children: [
                                        Text(
                                          CurrencyFormatter.format(
                                            item['product']['price'] *
                                                item['quantity'],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.remove),
                                          onPressed: () => removeFromCart(
                                            cart.indexOf(item),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(),
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
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: completeSale,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF667EEA),
                                  minimumSize: const Size(double.infinity, 50),
                                ),
                                child: const Text(
                                  'Complete Sale',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  // History Tab
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
                                                style: TextStyle(
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
