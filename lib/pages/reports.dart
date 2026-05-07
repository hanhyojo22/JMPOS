import 'package:flutter/material.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.book, size: 72),
          SizedBox(height: 16),
          Text('Reports and summaries'),
        ],
      ),
    );
  }
}
