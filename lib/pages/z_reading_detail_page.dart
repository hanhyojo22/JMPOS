import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pos_app/database/database_helper.dart';
import 'package:pos_app/utils/currency.dart';

class ZReadingDetailPage extends StatefulWidget {
  const ZReadingDetailPage({super.key, required this.readingId});

  final int readingId;

  @override
  State<ZReadingDetailPage> createState() => _ZReadingDetailPageState();
}

class _ZReadingDetailPageState extends State<ZReadingDetailPage> {
  Map<String, Object?>? _reading;
  List<Map<String, Object?>> _receipts = const [];
  bool _loading = true;
  String? _error;

  static const _primaryText = Color(0xFF1F2937);
  static const _secondaryText = Color(0xFF6B7280);
  static const _success = Color(0xFF10B981);
  static const _blue = Color(0xFF2378F7);
  static const _red = Color(0xFFD32F2F);
  static const _pageBg = Color(0xFFF5F4FC);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = await DatabaseHelper.instance.database;
      await DatabaseHelper.instance.ensureShiftSchema();
      final rows = await db.rawQuery(
        '''
        SELECT
          shift_readings.*,
          COALESCE(NULLIF(created_user.full_name, ''), shift_readings.created_by) AS created_by_display_name,
          shifts.status AS shift_status,
          shifts.opened_by,
          COALESCE(NULLIF(opened_user.full_name, ''), shifts.opened_by) AS opened_by_display_name,
          shifts.opened_at,
          shifts.closed_by,
          COALESCE(NULLIF(closed_user.full_name, ''), shifts.closed_by) AS closed_by_display_name,
          shifts.closed_at,
          shifts.z_reading_number
        FROM shift_readings
        LEFT JOIN shifts ON shifts.id = shift_readings.shift_id
        LEFT JOIN users AS created_user ON created_user.username = shift_readings.created_by
        LEFT JOIN users AS opened_user ON opened_user.username = shifts.opened_by
        LEFT JOIN users AS closed_user ON closed_user.username = shifts.closed_by
        WHERE shift_readings.id = ?
        LIMIT 1
        ''',
        [widget.readingId],
      );

      if (rows.isEmpty) {
        throw Exception('Reading was not found.');
      }

      final shiftId = (rows.first['shift_id'] as num?)?.toInt();
      final receipts = shiftId == null
          ? <Map<String, Object?>>[]
          : await db.rawQuery(
              '''
              SELECT
                MIN(id) AS id,
                COALESCE(NULLIF(receipt_number,''),'INV-'||printf('%06d',MIN(id))) AS receipt_number,
                GROUP_CONCAT(product_name, ', ') AS product_names,
                SUM(quantity) AS quantity,
                SUM(total) - MAX(COALESCE(receipt_discount_amount,0)) AS total,
                MAX(COALESCE(voided_at,'')) AS voided_at,
                MIN(created_at) AS created_at
              FROM sales
              WHERE shift_id = ?
              GROUP BY COALESCE(NULLIF(receipt_number,''),substr(created_at,1,19))
              ORDER BY MIN(created_at) ASC, MIN(id) ASC
              ''',
              [shiftId],
            );

      if (!mounted) return;
      setState(() {
        _reading = Map<String, Object?>.from(rows.first);
        _receipts = receipts;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        title: Text(_pageTitle),
        backgroundColor: Colors.white,
        foregroundColor: _primaryText,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _message(_error!)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _headerCard(),
                  const SizedBox(height: 14),
                  _cashSummaryCard(),
                  const SizedBox(height: 14),
                  _shiftInfoCard(),
                  const SizedBox(height: 14),
                  _receiptsCard(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _message(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }

  Widget _headerCard() {
    final reading = _reading!;
    final isXReading = _isXReading(reading);
    final title = isXReading
        ? 'X-${reading['id']}'
        : reading['z_reading_number']?.toString().trim().isNotEmpty == true
        ? reading['z_reading_number'].toString()
        : 'Z-${reading['id']}';
    final createdAt = _parseDate(reading['created_at']);
    final overShort = _money(reading['over_short']);

    return _card(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: _success.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.point_of_sale_rounded,
                  color: _success,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _primaryText,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_dateText(createdAt)} - ${_timeText(createdAt)}',
                      style: const TextStyle(
                        color: _secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              isXReading
                  ? _typePill('Snapshot', _blue)
                  : _statusPill(overShort),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _summaryText(
                  label: isXReading ? 'Created By' : 'Closed By',
                  value:
                      reading['created_by_display_name']?.toString() ??
                      reading['created_by']?.toString() ??
                      'unknown',
                  valueColor: _primaryText,
                ),
              ),
              Expanded(
                child: _summaryText(
                  label: 'Expected Cash',
                  value: CurrencyFormatter.format(
                    _money(reading['expected_cash']),
                  ),
                  valueColor: _blue,
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

  Widget _cashSummaryCard() {
    final reading = _reading!;
    final isXReading = _isXReading(reading);
    final overShort = _money(reading['over_short']);
    final overShortColor = overShort == 0
        ? _primaryText
        : overShort > 0
        ? _success
        : _red;
    return _card(
      child: Column(
        children: [
          _totalRow('Opening cash', _moneyText(reading['opening_cash'])),
          const SizedBox(height: 12),
          _totalRow('Sales total', _moneyText(reading['sales_total'])),
          const SizedBox(height: 12),
          _totalRow('Void total', _moneyText(reading['void_total'])),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1),
          ),
          _totalRow(
            'Expected cash',
            _moneyText(reading['expected_cash']),
            valueColor: _blue,
            large: true,
          ),
          if (!isXReading) ...[
            const SizedBox(height: 12),
            _totalRow('Counted cash', _moneyText(reading['counted_cash'])),
            const SizedBox(height: 12),
            _totalRow(
              'Over / Short',
              _moneyText(reading['over_short']),
              valueColor: overShortColor,
              large: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _shiftInfoCard() {
    final reading = _reading!;
    final isXReading = _isXReading(reading);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('Shift'),
          const SizedBox(height: 14),
          _infoRow('Shift ID', '#${reading['shift_id']}'),
          _infoRow(
            'Opened by',
            reading['opened_by_display_name']?.toString() ??
                reading['opened_by']?.toString() ??
                'unknown',
          ),
          _infoRow('Opened at', _dateTimeText(reading['opened_at'])),
          if (!isXReading) ...[
            _infoRow(
              'Closed by',
              reading['closed_by_display_name']?.toString() ??
                  reading['closed_by']?.toString() ??
                  'unknown',
            ),
            _infoRow('Closed at', _dateTimeText(reading['closed_at'])),
          ],
          _infoRow(
            'Receipts',
            '${(reading['receipt_count'] as num?)?.toInt() ?? 0}',
          ),
          _infoRow(
            'Items sold',
            '${(reading['item_count'] as num?)?.toInt() ?? 0}',
          ),
        ],
      ),
    );
  }

  Widget _receiptsCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('Receipts'),
          const SizedBox(height: 14),
          if (_receipts.isEmpty)
            const Text(
              'No receipts were recorded in this shift.',
              style: TextStyle(color: _secondaryText),
            )
          else
            ..._receipts.map(_receiptRow),
        ],
      ),
    );
  }

  Widget _receiptRow(Map<String, Object?> receipt) {
    final total = _money(receipt['total']);
    final isVoided = (receipt['voided_at']?.toString() ?? '').isNotEmpty;
    final createdAt = _parseDate(receipt['created_at']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  receipt['receipt_number']?.toString() ?? 'Receipt',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _primaryText,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_timeText(createdAt)} • ${(receipt['quantity'] as num?)?.toInt() ?? 0} item${((receipt['quantity'] as num?)?.toInt() ?? 0) == 1 ? '' : 's'}${isVoided ? ' • Voided' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isVoided ? _red : _secondaryText,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            CurrencyFormatter.format(total),
            style: TextStyle(
              color: isVoided ? _red : _primaryText,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(double overShort) {
    final color = overShort == 0
        ? _success
        : overShort > 0
        ? const Color(0xFFF59E0B)
        : _red;
    final label = overShort == 0
        ? 'Balanced'
        : overShort > 0
        ? 'Over'
        : 'Short';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _typePill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _summaryText({
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
        Text(
          label,
          style: const TextStyle(color: _secondaryText, fontSize: 12),
        ),
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

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(color: _secondaryText, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: _primaryText,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: _primaryText,
        fontSize: 14,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  String _moneyText(Object? value) => CurrencyFormatter.format(_money(value));

  double _money(Object? value) => (value as num?)?.toDouble() ?? 0;

  String get _pageTitle {
    final reading = _reading;
    if (reading == null) return 'Reading Details';
    return _isXReading(reading) ? 'X Reading Details' : 'Z Reading Details';
  }

  bool _isXReading(Map<String, Object?> reading) {
    return reading['type']?.toString().toLowerCase() == 'x';
  }

  DateTime? _parseDate(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text)?.toLocal();
  }

  String _dateText(DateTime? value) {
    if (value == null) return '-';
    return DateFormat('MMM d, yyyy').format(value);
  }

  String _timeText(DateTime? value) {
    if (value == null) return '-';
    return DateFormat('h:mm a').format(value);
  }

  String _dateTimeText(Object? value) {
    final parsed = _parseDate(value);
    if (parsed == null) return '-';
    return DateFormat('MMM d, yyyy h:mm a').format(parsed);
  }
}
