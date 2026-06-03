import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_app/database/database_helper.dart';
import 'package:pos_app/models/receipt_discount_preset.dart';

class DiscountsSettingsPage extends StatefulWidget {
  const DiscountsSettingsPage({super.key, required this.currentUsername});

  final String currentUsername;

  @override
  State<DiscountsSettingsPage> createState() => _DiscountsSettingsPageState();
}

class _DiscountsSettingsPageState extends State<DiscountsSettingsPage> {
  static const _green = Color(0xFF0F6E56);
  static const _surface = Color(0xFFF4F5FF);
  static const _border = Color(0xFFEEEEEE);
  static const _textPrimary = Color(0xFF1A1F36);
  static const _textSecondary = Color(0xFF6B7280);
  static const _danger = Color(0xFFDC2626);

  final List<ReceiptDiscountPreset> _discounts = [];
  bool _loading = true;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _pageSurface => _isDark ? const Color(0xFF0F172A) : _surface;
  Color get _cardSurface => _isDark ? const Color(0xFF111827) : Colors.white;
  Color get _lineColor => _isDark ? const Color(0xFF253047) : _border;
  Color get _primaryText => _isDark ? const Color(0xFFF8FAFC) : _textPrimary;
  Color get _secondaryText =>
      _isDark ? const Color(0xFFCBD5E1) : _textSecondary;

  @override
  void initState() {
    super.initState();
    _loadDiscounts();
  }

  Future<void> _loadDiscounts() async {
    setState(() => _loading = true);
    try {
      final discounts = await DatabaseHelper.instance.getReceiptDiscounts(
        includeDisabled: true,
      );
      if (!mounted) return;
      setState(() {
        _discounts
          ..clear()
          ..addAll(discounts);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('Could not load discounts: $e');
    }
  }

  Future<void> _showDiscountDialog(ReceiptDiscountPreset? discount) async {
    final nameCtrl = TextEditingController(text: discount?.name ?? '');
    final percentCtrl = TextEditingController(
      text: discount == null ? '' : _formatPercent(discount.percent),
    );
    var enabled = discount?.enabled ?? true;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(discount == null ? 'Add Discount' : 'Edit Discount'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: percentCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    TextInputFormatter.withFunction(_formatPercentEdit),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Percent',
                    suffixText: '%',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enabled at checkout'),
                  value: enabled,
                  onChanged: (value) => setDialogState(() => enabled = value),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final percent = double.tryParse(
                    _sanitizePercent(percentCtrl.text),
                  );
                  if (nameCtrl.text.trim().isEmpty ||
                      percent == null ||
                      percent <= 0 ||
                      percent > 100) {
                    _showMessage('Enter a name and percent from 1 to 100.');
                    return;
                  }
                  try {
                    await DatabaseHelper.instance.saveReceiptDiscount(
                      id: discount?.id,
                      name: nameCtrl.text,
                      percent: percent,
                      enabled: enabled,
                      actorUsername: widget.currentUsername,
                    );
                    if (!mounted || !dialogContext.mounted) return;
                    Navigator.pop(dialogContext);
                    await _loadDiscounts();
                  } catch (e) {
                    _showMessage('Could not save discount: $e');
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    nameCtrl.dispose();
    percentCtrl.dispose();
  }

  Future<void> _deleteDiscount(ReceiptDiscountPreset discount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Discount'),
        content: Text('Remove "${discount.name}" from checkout discounts?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: _danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || discount.id == null) return;

    try {
      await DatabaseHelper.instance.deleteReceiptDiscount(
        id: discount.id!,
        actorUsername: widget.currentUsername,
      );
      await _loadDiscounts();
    } catch (e) {
      _showMessage('Could not delete discount: $e');
    }
  }

  Future<void> _toggleDiscount(
    ReceiptDiscountPreset discount,
    bool value,
  ) async {
    if (discount.id == null) return;
    try {
      await DatabaseHelper.instance.setReceiptDiscountEnabled(
        id: discount.id!,
        enabled: value,
        actorUsername: widget.currentUsername,
      );
      await _loadDiscounts();
    } catch (e) {
      _showMessage('Could not update discount: $e');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatPercent(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }

  static String _sanitizePercent(String value) {
    final normalized = value.trim().replaceAll(',', '');
    final buffer = StringBuffer();
    var hasDecimal = false;
    var decimalCount = 0;

    for (final codeUnit in normalized.codeUnits) {
      final char = String.fromCharCode(codeUnit);
      final isDigit = codeUnit >= 48 && codeUnit <= 57;
      if (isDigit) {
        if (hasDecimal) {
          if (decimalCount >= 2) continue;
          decimalCount++;
        }
        buffer.write(char);
        continue;
      }
      if (char == '.' && !hasDecimal) {
        hasDecimal = true;
        buffer.write(buffer.isEmpty ? '0.' : '.');
      }
    }
    return buffer.toString();
  }

  static TextEditingValue _formatPercentEdit(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final sanitized = _sanitizePercent(newValue.text);
    if (sanitized == newValue.text) return newValue;
    return TextEditingValue(
      text: sanitized,
      selection: TextSelection.collapsed(offset: sanitized.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageSurface,
      appBar: AppBar(
        backgroundColor: _pageSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('Discounts', style: TextStyle(color: _primaryText)),
        iconTheme: IconThemeData(color: _primaryText),
        actions: [
          IconButton(
            onPressed: () => _showDiscountDialog(null),
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add discount',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  'Create and manage discounts used during checkout.',
                  style: TextStyle(color: _secondaryText, fontSize: 13),
                ),
                const SizedBox(height: 16),
                if (_discounts.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _cardSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _lineColor),
                    ),
                    child: Text(
                      'No discounts yet. Add one to show it in checkout.',
                      style: TextStyle(color: _secondaryText),
                    ),
                  )
                else
                  for (final discount in _discounts) ...[
                    _DiscountSettingsCard(
                      discount: discount,
                      primaryText: _primaryText,
                      secondaryText: _secondaryText,
                      cardSurface: _cardSurface,
                      lineColor: _lineColor,
                      accent: _green,
                      onToggle: (value) => _toggleDiscount(discount, value),
                      onEdit: () => _showDiscountDialog(discount),
                      onDelete: () => _deleteDiscount(discount),
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => _showDiscountDialog(null),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Discount'),
            ),
          ),
        ),
      ),
    );
  }
}

class _DiscountSettingsCard extends StatelessWidget {
  const _DiscountSettingsCard({
    required this.discount,
    required this.primaryText,
    required this.secondaryText,
    required this.cardSurface,
    required this.lineColor,
    required this.accent,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final ReceiptDiscountPreset discount;
  final Color primaryText;
  final Color secondaryText;
  final Color cardSurface;
  final Color lineColor;
  final Color accent;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final percent = discount.percent == discount.percent.roundToDouble()
        ? discount.percent.toStringAsFixed(0)
        : discount.percent.toStringAsFixed(2);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: lineColor),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Icon(Icons.local_offer_rounded, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  discount.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: primaryText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$percent% discount',
                  style: TextStyle(color: secondaryText, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(value: discount.enabled, onChanged: onToggle),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
            color: _DiscountsSettingsPageState._danger,
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }
}
