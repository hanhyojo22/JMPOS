import 'package:flutter/material.dart';
import 'package:pos_app/database/database_helper.dart';
import 'package:pos_app/utils/currency.dart';

class RecentSalesPage extends StatefulWidget {
  const RecentSalesPage({
    super.key,
    required this.saleId,
    required this.currentUsername,
  });

  final int saleId;
  final String currentUsername;

  @override
  State<RecentSalesPage> createState() => _RecentSalesPageState();
}

class _RecentSalesPageState extends State<RecentSalesPage> {
  static const Color _primary = Color(0xFF5C6BC0);
  static const Color _surface = Color(0xFFF4F5FF);
  static const Color _textPrimary = Color(0xFF1A1F36);
  static const Color _textSecondary = Color(0xFF6B7280);
  static const Color _success = Color(0xFF10B981);

  Map<String, dynamic>? _sale;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _voiding = false;
  String? _error;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _pageSurface => _isDark ? const Color(0xFF0F172A) : _surface;
  Color get _panelSurface => _isDark ? const Color(0xFF111827) : Colors.white;
  Color get _primaryText => _isDark ? const Color(0xFFF8FAFC) : _textPrimary;
  Color get _secondaryText =>
      _isDark ? const Color(0xFFCBD5E1) : _textSecondary;

  @override
  void initState() {
    super.initState();
    _loadSale();
  }

  Future<void> _loadSale() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = await DatabaseHelper.instance.database;
      await DatabaseHelper.instance.ensureSalesSchema();

      final rows = await db.rawQuery(
        '''
        SELECT
          sales.id,
          sales.product_id,
          sales.product_name,
          sales.quantity,
          sales.price,
          sales.total,
          sales.voided_at,
          sales.voided_by,
          sales.void_reason,
          sales.created_at,
          products.category AS category,
          products.barcode AS barcode
        FROM sales
        LEFT JOIN products ON products.id = sales.product_id
        WHERE sales.id = ?
        LIMIT 1
        ''',
        [widget.saleId],
      );

      final selectedSale = rows.isEmpty ? null : rows.first;
      var transactionItems = <Map<String, dynamic>>[];

      if (selectedSale != null) {
        final createdAt = DateTime.tryParse(
          selectedSale['created_at'].toString(),
        );

        if (createdAt != null) {
          final start = createdAt.subtract(const Duration(seconds: 1));
          final end = createdAt.add(const Duration(seconds: 1));

          transactionItems = await db.rawQuery(
            '''
            SELECT
              sales.id,
              sales.product_id,
              sales.product_name,
              sales.quantity,
              sales.price,
              sales.total,
              sales.voided_at,
              sales.voided_by,
              sales.void_reason,
              sales.created_at,
              products.category AS category,
              products.barcode AS barcode
            FROM sales
            LEFT JOIN products ON products.id = sales.product_id
            WHERE sales.created_at >= ? AND sales.created_at <= ?
            ORDER BY sales.id ASC
            ''',
            [start.toIso8601String(), end.toIso8601String()],
          );
        }

        if (transactionItems.isEmpty) {
          transactionItems = [selectedSale];
        }
      }

      if (!mounted) return;
      setState(() {
        _sale = selectedSale;
        _items = transactionItems;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load sale: $e';
        _loading = false;
      });
    }
  }

  DateTime? _createdAt() {
    final raw = _sale?['created_at']?.toString();
    if (raw == null || raw.isEmpty) return null;
    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return null;
    }
  }

  String _dateText(DateTime? date) {
    if (date == null) return 'Unknown date';
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
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _timeText(DateTime? date) {
    if (date == null) return '';
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  bool get _isVoided => (_sale?['voided_at']?.toString() ?? '').isNotEmpty;

  Future<void> _confirmVoidSale() async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Void sale'),
        content: TextField(
          controller: reasonController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason',
            hintText: 'Optional note',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Void', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      reasonController.dispose();
      return;
    }

    setState(() => _voiding = true);
    try {
      final success = await DatabaseHelper.instance.voidSaleTransaction(
        saleId: widget.saleId,
        user: widget.currentUsername,
        reason: reasonController.text,
      );

      if (!mounted) return;
      setState(() => _voiding = false);

      if (success) {
        await _loadSale();
        if (!mounted) return;
        _showActionMessage('Sale voided and stock restored');
        Navigator.pop(context, true);
      } else {
        _showActionMessage('Sale record not found');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _voiding = false);
      _showActionMessage('Error: $e');
    } finally {
      reasonController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageSurface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _panelSurface,
        foregroundColor: _primaryText,
        centerTitle: true,
        title: Text(
          _sale == null ? 'Sale Details' : 'Sale #${_sale!['id']}',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : _error != null
          ? _buildMessage(_error!, Icons.error_outline_rounded)
          : _sale == null
          ? _buildMessage('Sale record not found', Icons.receipt_long_outlined)
          : Stack(
              children: [
                RefreshIndicator(
                  color: _primary,
                  onRefresh: _loadSale,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
                    children: [_buildSaleDetails()],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _stickyReceiptActions(),
                ),
              ],
            ),
    );
  }

  Widget _buildSaleDetails() {
    final sale = _sale!;
    final createdAt = _createdAt();
    final transactionTotal = _items.fold<double>(
      0.0,
      (sum, item) => sum + ((item['total'] as num?)?.toDouble() ?? 0.0),
    );
    const discount = 0.0;
    final subtotal = transactionTotal + discount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _receiptHeaderCard(
          receiptId: '#${sale['id']}',
          createdAt: createdAt,
          total: transactionTotal,
        ),
        const SizedBox(height: 14),
        _itemsTableCard(),
        const SizedBox(height: 14),
        _totalsCard(
          subtotal: subtotal,
          discount: discount,
          total: transactionTotal,
        ),
        const SizedBox(height: 14),
        _noteCard(),
      ],
    );
  }

  Widget _receiptHeaderCard({
    required String receiptId,
    required DateTime? createdAt,
    required double total,
  }) {
    return _receiptCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFF2F80ED).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: Color(0xFF2378F7),
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sale $receiptId',
                      style: TextStyle(
                        color: _primaryText,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_dateText(createdAt)} - ${_timeText(createdAt)}',
                      style: TextStyle(color: _secondaryText, fontSize: 12),
                    ),
                  ],
                ),
              ),
              _statusPill(),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _paymentSummaryText(
                  label: 'Payment Method',
                  value: 'Cash',
                  valueColor: _success,
                ),
              ),
              Expanded(
                child: _paymentSummaryText(
                  label: 'Total Amount',
                  value: CurrencyFormatter.format(total),
                  valueColor: const Color(0xFF2378F7),
                  alignEnd: true,
                  large: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusPill() {
    final isVoided = _isVoided;
    final color = isVoided ? Colors.red : _success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isVoided ? 'Voided' : 'Completed',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _paymentSummaryText({
    required String label,
    required String value,
    required Color valueColor,
    bool alignEnd = false,
    bool large = false,
  }) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: _secondaryText, fontSize: 12)),
        const SizedBox(height: 6),
        Text(
          value,
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
          style: TextStyle(
            color: valueColor,
            fontSize: large ? 22 : 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _itemsTableCard() {
    return _receiptCard(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Items',
            style: TextStyle(
              color: _primaryText,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                flex: 6,
                child: Text(
                  'Item',
                  style: TextStyle(color: _secondaryText, fontSize: 11),
                ),
              ),
              _tableHeader('Qty', flex: 2),
              _tableHeader('Price', flex: 3),
              _tableHeader('Total', flex: 3),
            ],
          ),
          const SizedBox(height: 12),
          ..._items.map(_itemTableRow),
        ],
      ),
    );
  }

  Widget _tableHeader(String text, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: TextStyle(color: _secondaryText, fontSize: 11),
      ),
    );
  }

  Widget _itemTableRow(Map<String, dynamic> item) {
    final productName = item['product_name']?.toString() ?? 'Unknown product';
    final category = item['category']?.toString() ?? 'Item';
    final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
    final price = (item['price'] as num?)?.toDouble() ?? 0.0;
    final total = (item['total'] as num?)?.toDouble() ?? 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _primaryText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: _secondaryText),
                ),
              ],
            ),
          ),
          _tableValue('$quantity', flex: 2),
          _tableValue(CurrencyFormatter.format(price), flex: 3),
          _tableValue(CurrencyFormatter.format(total), flex: 3),
        ],
      ),
    );
  }

  Widget _tableValue(String text, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: TextAlign.right,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: _primaryText,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _totalsCard({
    required double subtotal,
    required double discount,
    required double total,
  }) {
    return _receiptCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _totalRow('Subtotal', CurrencyFormatter.format(subtotal)),
          const SizedBox(height: 12),
          _totalRow(
            'Discount',
            '- ${CurrencyFormatter.format(discount)}',
            valueColor: _success,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1),
          ),
          _totalRow(
            'Total',
            CurrencyFormatter.format(total),
            valueColor: const Color(0xFF2378F7),
            large: true,
          ),
        ],
      ),
    );
  }

  Widget _totalRow(
    String label,
    String value, {
    Color? valueColor,
    bool large = false,
  }) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: _primaryText,
            fontSize: large ? 15 : 13,
            fontWeight: large ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? _primaryText,
            fontSize: large ? 22 : 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _noteCard() {
    final isVoided = _isVoided;
    final reason = _sale?['void_reason']?.toString();
    return _receiptCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFA855F7).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.sticky_note_2_outlined,
              color: Color(0xFFA855F7),
              size: 25,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isVoided ? 'Void Reason' : 'Note',
                style: TextStyle(
                  color: _primaryText,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isVoided && reason != null && reason.isNotEmpty
                    ? reason
                    : 'No note',
                style: TextStyle(color: _secondaryText, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _receiptActions() {
    return Row(
      children: [
        Expanded(child: _printReceiptButton()),
        const SizedBox(width: 12),
        Expanded(child: _voidSaleButton()),
      ],
    );
  }

  Widget _stickyReceiptActions() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: _pageSurface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _isDark ? 0.24 : 0.08),
              blurRadius: 16,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: _receiptActions(),
      ),
    );
  }

  Widget _printReceiptButton() {
    return OutlinedButton.icon(
      onPressed: () => _showActionMessage('Print receipt is coming soon'),
      icon: const Icon(Icons.print_rounded, size: 18),
      label: const Text('Print Receipt'),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF2378F7),
        side: const BorderSide(color: Color(0xFF2378F7)),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _voidSaleButton() {
    final isVoided = _isVoided;
    return ElevatedButton.icon(
      onPressed: isVoided || _voiding ? null : _confirmVoidSale,
      icon: _voiding
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(
              isVoided ? Icons.block_rounded : Icons.cancel_outlined,
              size: 18,
            ),
      label: Text(isVoided ? 'Voided' : 'Void Sale'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red,
        disabledBackgroundColor: Colors.red.withValues(alpha: 0.38),
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showActionMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _receiptCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panelSurface,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDark ? 0.18 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildMessage(String message, IconData icon) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _secondaryText, size: 48),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: _secondaryText, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
