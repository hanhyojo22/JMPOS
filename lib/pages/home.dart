import 'dart:io';

import 'package:flutter/material.dart';
import 'add_products.dart';
import 'products.dart';
import 'sales.dart';
import 'reports.dart';
import 'account_page.dart';
import 'staff_management.dart';
import 'package:pos_app/utils/greetings.dart';
import 'package:pos_app/database/database_helper.dart';
import 'package:pos_app/utils/currency.dart';

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
  int _selectedIndex = 0;

  double totalSales = 0;

  int totalTransactions = 0;

  List<Map<String, dynamic>> recentTransactions = [];

  @override
  void initState() {
    super.initState();

    loadRecentTransactions();
  }

  // LOAD RECENT TRANSACTIONS
  Future<void> loadRecentTransactions() async {
    final db = await DatabaseHelper.instance.database;

    final transactions = await db.rawQuery('''

      SELECT

        sales.id,
        sales.product_name,
        sales.total,
        sales.created_at,

        products.image_url

      FROM sales

      LEFT JOIN products
      ON sales.product_id =
         products.id

      ORDER BY sales.id DESC

      LIMIT 10

    ''');

    double salesTotal = 0;

    for (final item in transactions) {
      salesTotal += (item['total'] as num).toDouble();
    }

    setState(() {
      totalSales = salesTotal;

      totalTransactions = transactions.length;

      recentTransactions = transactions.map((sale) {
        final createdAt = DateTime.parse(sale['created_at'].toString());

        return {
          'title': sale['product_name'],

          'subtitle':
              '${createdAt.month}/${createdAt.day}/${createdAt.year} • '
              '${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}',

          'amount': sale['total'],

          'imagePath': sale['image_url'] ?? '',
        };
      }).toList();
    });
  }

  void _openAccount() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AccountPage(username: widget.username)),
    );
  }

  Widget _buildPageContent() {
    switch (_selectedIndex) {
      case 1:
        return const ProductsPage();

      case 2:
        return const AddProductsPage();

      case 3:
        return const SalesPage();

      case 4:
        if (widget.role == 'admin') {
          return const ReportsPage();
        }

        return const SalesPage();

      case 5:
        if (widget.role == 'admin') {
          return const StaffManagementPage();
        }

        break;
    }

    return RefreshIndicator(
      onRefresh: loadRecentTransactions,

      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            // DASHBOARD CARD
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
                    color: Colors.black.withValues(alpha: 0.12),

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
                              color: Colors.white.withValues(alpha: 0.8),

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
                            vertical: 16,

                            horizontal: 18,
                          ),

                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),

                            borderRadius: BorderRadius.circular(20),

                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),

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

                                    color: Colors.white.withValues(alpha: 0.9),

                                    size: 18,
                                  ),

                                  const SizedBox(width: 6),

                                  Text(
                                    'Transactions',

                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.9,
                                      ),

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
                            vertical: 16,

                            horizontal: 18,
                          ),

                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),

                            borderRadius: BorderRadius.circular(20),

                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),

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

                                    color: Colors.white.withValues(alpha: 0.9),

                                    size: 18,
                                  ),

                                  const SizedBox(width: 6),

                                  Text(
                                    'Avg. Order',

                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.9,
                                      ),

                                      fontSize: 12,

                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 8),

                              Text(
                                CurrencyFormatter.format(
                                  totalTransactions == 0
                                      ? 0
                                      : totalSales / totalTransactions,
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

            // RECENT TRANSACTIONS HEADER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),

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

            // TRANSACTION LIST
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),

              child: Column(
                children: recentTransactions.map((transaction) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),

                    child: ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(12),

                        child: transaction['imagePath'] != ''
                            ? Image.file(
                                File(transaction['imagePath']),

                                width: 56,

                                height: 56,

                                fit: BoxFit.cover,

                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    width: 56,

                                    height: 56,

                                    color: Colors.grey.shade200,

                                    child: const Icon(Icons.broken_image),
                                  );
                                },
                              )
                            : Container(
                                width: 56,

                                height: 56,

                                color: Colors.grey.shade200,

                                child: const Icon(Icons.shopping_bag),
                              ),
                      ),

                      title: Text(transaction['title']),

                      subtitle: Text(transaction['subtitle']),

                      trailing: Text(
                        CurrencyFormatter.format(transaction['amount']),

                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onNavBarTapped(int index) async {
    setState(() {
      _selectedIndex = index;
    });

    // REFRESH HOME
    if (index == 0) {
      await loadRecentTransactions();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(Greetings.getGreeting()),

            const SizedBox(width: 8),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),

              decoration: BoxDecoration(
                color: widget.role == 'admin'
                    ? Colors.red.withValues(alpha: 0.3)
                    : Colors.blue.withValues(alpha: 0.3),

                borderRadius: BorderRadius.circular(8),
              ),

              child: Text(
                widget.role.toUpperCase(),

                style: TextStyle(
                  fontSize: 12,

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
          GestureDetector(
            onTap: _openAccount,

            child: Container(
              margin: const EdgeInsets.only(right: 16),

              child: const Icon(Icons.account_circle, size: 32),
            ),
          ),
        ],
      ),

      body: _buildPageContent(),

      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
              onPressed: () {
                setState(() {
                  _selectedIndex = 3;
                });
              },

              backgroundColor: const Color(0xFF667EEA),

              tooltip: 'New Sales',

              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,

      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,

      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,

        onDestinationSelected: _onNavBarTapped,

        backgroundColor: Colors.white,

        elevation: 8,

        shadowColor: Colors.black.withValues(alpha: 0.1),

        indicatorColor: const Color(0xFF667EEA).withValues(alpha: 0.2),

        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,

        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),

            selectedIcon: Icon(Icons.home),

            label: 'Home',
          ),

          const NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),

            selectedIcon: Icon(Icons.inventory_2),

            label: 'Inventory',
          ),

          const NavigationDestination(
            icon: Icon(Icons.add_circle_outline, size: 32),

            selectedIcon: Icon(Icons.add_circle, size: 32),

            label: 'Add',
          ),

          const NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),

            selectedIcon: Icon(Icons.bar_chart),

            label: 'Sales',
          ),

          if (widget.role == 'admin')
            const NavigationDestination(
              icon: Icon(Icons.book_outlined),

              selectedIcon: Icon(Icons.book),

              label: 'Reports',
            ),

          if (widget.role == 'admin')
            const NavigationDestination(
              icon: Icon(Icons.people_outlined),

              selectedIcon: Icon(Icons.people),

              label: 'Staff',
            ),
        ],
      ),
    );
  }
}
