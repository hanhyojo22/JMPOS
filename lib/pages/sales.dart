import 'package:flutter/material.dart';
import 'package:pos_app/utils/currency.dart';

class SalesPage extends StatelessWidget {
  const SalesPage({super.key});

  final List<Map<String, dynamic>> salesHistory = const [
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

  double get totalSales =>
      salesHistory.fold(0.0, (sum, item) => sum + (item['total'] as double));

  int get totalOrders => salesHistory.length;

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
                    'Sales History',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Review product sales and recent transactions.',
                    style: TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16.0),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18.0),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
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
                                CurrencyFormatter.format(totalSales),
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
                                color: Colors.black.withOpacity(0.04),
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
                                '$totalOrders',
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
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10.0,
                                  vertical: 6.0,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.16),
                                  borderRadius: BorderRadius.circular(12.0),
                                ),
                                child: Text(
                                  entry['status'] as String,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.shopping_cart,
                                    size: 18,
                                    color: Colors.black54,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Qty ${entry['quantity']}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Text(
                                CurrencyFormatter.format(
                                  entry['total'] as double,
                                ),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
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
    );
  }
}
