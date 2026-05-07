import 'package:flutter/material.dart';
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

  Widget _buildPageContent() {
    switch (_selectedIndex) {
      case 1:
        return const ProductsPage();
      case 2:
        return const SalesPage();
      case 3:
        return const ReportsPage();
    }

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(16.0),
          padding: const EdgeInsets.all(16.0),
          width: double.infinity,
          height: 150,
          decoration: BoxDecoration(
            color: Colors.lightBlue,
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Total Sales Today',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                CurrencyFormatter.format(totalSales),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
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
            label: 'Products',
          ),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Sales'),
          NavigationDestination(icon: Icon(Icons.book), label: 'Reports'),
        ],
      ),
    );
  }
}
