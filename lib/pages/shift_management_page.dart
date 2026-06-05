import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pos_app/database/database_helper.dart';
import 'package:pos_app/utils/currency.dart';
import 'z_reading_detail_page.dart';

class ShiftManagementPage extends StatefulWidget {
  const ShiftManagementPage({
    super.key,
    required this.currentUsername,
    required this.currentRole,
    this.readOnly = false,
  });

  final String currentUsername;
  final String currentRole;
  final bool readOnly;

  @override
  State<ShiftManagementPage> createState() => _ShiftManagementPageState();
}

class _ShiftManagementPageState extends State<ShiftManagementPage> {
  Map<String, Object?>? _openShift;
  Map<String, Object?>? _summary;
  List<Map<String, Object?>> _readings = const [];
  List<Map<String, Object?>> _history = const [];
  bool _loading = true;
  bool _busy = false;

  bool get _isAdmin => widget.currentRole.toLowerCase() == 'admin';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await DatabaseHelper.instance.ensureShiftSchema();
      final openShift = await DatabaseHelper.instance.getOpenShift();
      Map<String, Object?>? summary;
      List<Map<String, Object?>> readings = const [];
      if (openShift != null) {
        final shiftId = (openShift['id'] as num).toInt();
        summary = await DatabaseHelper.instance.getShiftSummary(shiftId);
        readings = await DatabaseHelper.instance.getShiftReadings(
          shiftId: shiftId,
        );
      }
      final history = await DatabaseHelper.instance.getShiftHistory();
      if (!mounted) return;
      setState(() {
        _openShift = openShift;
        _summary = summary;
        _readings = readings;
        _history = history;
      });
    } catch (e) {
      _showSnack('Unable to load shift: $e', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openNewShift() async {
    final amount = await _askCashAmount(
      title: 'Open shift',
      label: 'Starting cash',
      action: 'Open shift',
    );
    if (amount == null) return;
    setState(() => _busy = true);
    try {
      await DatabaseHelper.instance.openShift(
        openingCash: amount,
        openedBy: widget.currentUsername,
      );
      _showSnack('Shift opened.');
      await _load();
    } catch (e) {
      _showSnack('$e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createXReading() async {
    final shift = _openShift;
    if (shift == null) return;
    setState(() => _busy = true);
    try {
      await DatabaseHelper.instance.createXReading(
        shiftId: (shift['id'] as num).toInt(),
        createdBy: widget.currentUsername,
      );
      _showSnack('X reading saved.');
      await _load();
    } catch (e) {
      _showSnack('$e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _closeWithZReading() async {
    if (!_isAdmin) {
      _showSnack(
        'Only admin users can close a shift with Z reading.',
        isError: true,
      );
      return;
    }
    final shift = _openShift;
    if (shift == null) return;
    final amount = await _askCashAmount(
      title: 'Z reading',
      label: 'Counted cash',
      action: 'Close shift',
    );
    if (amount == null) return;
    setState(() => _busy = true);
    try {
      await DatabaseHelper.instance.closeShiftWithZReading(
        shiftId: (shift['id'] as num).toInt(),
        countedCash: amount,
        closedBy: widget.currentUsername,
      );
      _showSnack('Z reading saved and shift closed.');
      await _load();
    } catch (e) {
      _showSnack('$e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<double?> _askCashAmount({
    required String title,
    required String label,
    required String action,
  }) async {
    final controller = TextEditingController(text: '0.00');
    final result = await showDialog<double>(
      context: context,
      builder: (context) {
        String? error;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: label,
                      prefixText: 'PHP ',
                      errorText: error,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final parsed = double.tryParse(
                      controller.text.trim().replaceAll(',', ''),
                    );
                    if (parsed == null || parsed < 0) {
                      setDialogState(() {
                        error = 'Enter a valid amount.';
                      });
                      return;
                    }
                    Navigator.pop(context, parsed);
                  },
                  child: Text(action),
                ),
              ],
            );
          },
        );
      },
    );
    return result;
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final open = _openShift != null;
    final summary = _summary ?? const <String, Object?>{};

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _HeaderCard(
            open: open,
            openedBy: _openShift?['opened_by']?.toString(),
            openedAt: _openShift?['opened_at']?.toString(),
          ),
          const SizedBox(height: 16),
          if (open) ...[
            _TotalsGrid(summary: summary),
            const SizedBox(height: 16),
          ],
          if (!widget.readOnly)
            _ActionBar(
              open: open,
              busy: _busy,
              canZReading: _isAdmin,
              onOpenShift: _openNewShift,
              onXReading: _createXReading,
              onZReading: _closeWithZReading,
            ),
          const SizedBox(height: 18),
          _SectionTitle(
            title: open ? 'Current shift readings' : 'Recent shifts',
          ),
          if (open)
            _ReadingList(readings: _readings, onOpenReading: _openReading)
          else
            _ShiftHistoryList(history: _history),
        ],
      ),
    );
  }

  Future<void> _openReading(Map<String, Object?> reading) async {
    final readingId = (reading['id'] as num?)?.toInt();
    if (readingId == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ZReadingDetailPage(readingId: readingId),
      ),
    );
    if (mounted) await _load();
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.open,
    required this.openedBy,
    required this.openedAt,
  });

  final bool open;
  final String? openedBy;
  final String? openedAt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: open ? Colors.green.shade50 : Colors.grey.shade100,
            child: Icon(
              open ? Icons.lock_open_rounded : Icons.lock_rounded,
              color: open ? Colors.green.shade700 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  open ? 'Shift open' : 'No open shift',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  open
                      ? 'Opened by ${openedBy ?? 'unknown'} at ${_formatDate(openedAt)}'
                      : 'Open a shift before completing sales.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalsGrid extends StatelessWidget {
  const _TotalsGrid({required this.summary});

  final Map<String, Object?> summary;

  @override
  Widget build(BuildContext context) {
    final openingCash = _money(summary['opening_cash']);
    final salesTotal = _money(summary['sales_total']);
    final expectedCash = openingCash + salesTotal;
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.75,
      ),
      children: [
        _TotalCard(label: 'Opening cash', value: openingCash),
        _TotalCard(label: 'Sales total', value: salesTotal),
        _TotalCard(label: 'Expected cash', value: expectedCash),
        _TotalCard(
          label: 'Receipts',
          textValue: '${(summary['receipt_count'] as num?)?.toInt() ?? 0}',
        ),
      ],
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.label, this.value, this.textValue});

  final String label;
  final double? value;
  final String? textValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Text(
            textValue ?? CurrencyFormatter.format(value ?? 0),
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.open,
    required this.busy,
    required this.canZReading,
    required this.onOpenShift,
    required this.onXReading,
    required this.onZReading,
  });

  final bool open;
  final bool busy;
  final bool canZReading;
  final VoidCallback onOpenShift;
  final VoidCallback onXReading;
  final VoidCallback onZReading;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (!open)
          Expanded(
            child: ElevatedButton.icon(
              onPressed: busy ? null : onOpenShift,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Open shift'),
            ),
          )
        else ...[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: busy ? null : onXReading,
              icon: const Icon(Icons.receipt_long_rounded),
              label: const Text('X reading'),
            ),
          ),
          if (canZReading) ...[
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: busy ? null : onZReading,
                icon: const Icon(Icons.task_alt_rounded),
                label: const Text('Z reading'),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _ReadingList extends StatelessWidget {
  const _ReadingList({required this.readings, required this.onOpenReading});

  final List<Map<String, Object?>> readings;
  final ValueChanged<Map<String, Object?>> onOpenReading;

  @override
  Widget build(BuildContext context) {
    if (readings.isEmpty) {
      return const _EmptyState(text: 'No readings saved for this shift.');
    }
    return Column(
      children: readings.map((reading) {
        final type = reading['type']?.toString().toUpperCase() ?? 'X';
        return _ListCard(
          title: '$type reading',
          subtitle:
              '${_formatDate(reading['created_at']?.toString())} by ${reading['created_by'] ?? 'unknown'}',
          trailing: CurrencyFormatter.format(_money(reading['expected_cash'])),
          onTap: () => onOpenReading(reading),
        );
      }).toList(),
    );
  }
}

class _ShiftHistoryList extends StatelessWidget {
  const _ShiftHistoryList({required this.history});

  final List<Map<String, Object?>> history;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const _EmptyState(text: 'No shift history yet.');
    }
    return Column(
      children: history.map((shift) {
        final isOpen = shift['status']?.toString() == 'open';
        return _ListCard(
          title: isOpen
              ? 'Open shift'
              : shift['z_reading_number']?.toString() ?? 'Closed shift',
          subtitle:
              'Opened ${_formatDate(shift['opened_at']?.toString())} by ${shift['opened_by'] ?? 'unknown'}',
          trailing: CurrencyFormatter.format(_money(shift['expected_cash'])),
        );
      }).toList(),
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              Text(
                trailing,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade500),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Center(child: Text(text)),
    );
  }
}

double _money(Object? value) => (value as num?)?.toDouble() ?? 0;

String _formatDate(String? value) {
  if (value == null || value.isEmpty) return '-';
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  return DateFormat('MMM d, yyyy h:mm a').format(parsed.toLocal());
}
