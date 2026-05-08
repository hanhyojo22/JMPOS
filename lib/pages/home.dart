import 'package:flutter/material.dart';
import 'add_products.dart';
import 'products.dart';
import 'sales.dart';
import 'reports.dart';
import 'package:pos_app/utils/greetings.dart';
import 'package:pos_app/utils/currency.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.title});

  final String title;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  double totalSales = 1234.56; // Placeholder for total sales today
  int totalTransactions = 42; // Placeholder for total transactions today

  final List<Map<String, dynamic>> recentTransactions = [
    {
      'title': 'Twinpack Nescafe',
      'subtitle': 'Today · 10:23 AM',
      'amount': 8.75,
      'imagePath': 'lib/assets/twinpack nescafe.png',
    },
    {
      'title': 'Lucky Pancit Cantoon',
      'subtitle': 'Today · 9:15 AM',
      'amount': 24.90,
      'imagePath': 'lib/assets/lucky pancit cantoon.png',
    },
    {
      'title': 'Sardines',
      'subtitle': 'Yesterday · 7:42 PM',
      'amount': 32.20,
      'imagePath': 'lib/assets/Sardines.png',
    },
    {
      'title': 'Lucky Mae',
      'subtitle': 'Yesterday · 6:15 PM',
      'amount': 15.50,
      'imagePath': 'lib/assets/lucky mae.png',
    },
    {
      'title': 'Birds Tree',
      'subtitle': 'Yesterday · 5:30 PM',
      'amount': 12.75,
      'imagePath': 'lib/assets/birds tree.png',
    },
  ];

  Widget _buildPageContent() {
    switch (_selectedIndex) {
      case 1:
        return const ProductsPage();
      case 2:
        return const AddProductsPage();
      case 3:
        return const SalesPage();
      case 4:
        return const ReportsPage();
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.all(16.0),
            padding: const EdgeInsets.all(24.0),
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
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
                          'Today\'s Revenue',
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
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.all(12.0),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.trending_up,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  CurrencyFormatter.format(totalSales),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 16.0,
                          horizontal: 18.0,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20.0),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.receipt_long,
                                  color: Colors.white.withOpacity(0.9),
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Transactions',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$totalTransactions',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 16.0,
                          horizontal: 18.0,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20.0),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.inventory_2,
                                  color: Colors.white.withOpacity(0.9),
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Avg. Order',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              CurrencyFormatter.format(
                                totalSales / totalTransactions,
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent Transactions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedIndex = 3;
                    });
                  },
                  child: const Text('View all'),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              children: recentTransactions.map((transaction) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 12.0),
                  child: ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(12.0),
                      child: Image.asset(
                        transaction['imagePath']!,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 56,
                            height: 56,
                            color: Colors.grey.shade300,
                            child: const Icon(Icons.image_not_supported),
                          );
                        },
                      ),
                    ),
                    title: Text(transaction['title'] as String),
                    subtitle: Text(transaction['subtitle'] as String),
                    trailing: Text(
                      CurrencyFormatter.format(transaction['amount'] as double),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _onNavBarTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(Greetings.getGreeting()),
        actions: const [
          Icon(Icons.account_circle, size: 32),
          SizedBox(width: 16),
        ],
      ),
      body: _buildPageContent(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onNavBarTapped,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.shopping_bag),
            label: 'Inventory',
          ),
          NavigationDestination(
            icon: Icon(Icons.add, size: 40),
            label: 'Add Products',
          ),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Sales'),
          NavigationDestination(icon: Icon(Icons.book), label: 'Reports'),
        ],
      ),
    );
  }
}
