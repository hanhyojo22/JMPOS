import 'package:flutter/material.dart';

class SalesPage extends StatelessWidget {
  const SalesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.bar_chart, size: 72),
          SizedBox(height: 16),
          Text('Sales analytics and charts'),
        ],
      ),
    );
  }
}
