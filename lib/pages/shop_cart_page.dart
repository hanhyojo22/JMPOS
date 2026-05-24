import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_app/utils/currency.dart';
import 'package:pos_app/utils/message_banner.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────
const _primary = Color(0xFF5C6BC0);
const _surface = Color(0xFFF4F5FF);
const _cardBg = Colors.white;
const _border = Color(0xFFEEEEEE);
const _textPrimary = Color(0xFF1A1F36);
const _textSecondary = Color(0xFF6B7280);
const _textTertiary = Color(0xFFAAAAAA);
const _purple = Color(0xFF534AB7);
const _purpleBg = Color(0xFFEEEDFE);
const _purpleBorder = Color(0xFFCECBF6);
const _green = Color(0xFF3B6D11);
const _greenBg = Color(0xFFEAF3DE);
const _greenBorder = Color(0xFFC0DD97);
const _red = Color(0xFFA32D2D);
const _redBg = Color(0xFFFCEBEB);
const _redBorder = Color(0xFFF7C1C1);

// ─── CartPage ─────────────────────────────────────────────────────────────────
class CartPage extends StatefulWidget {
  final List<Map<String, dynamic>> cart;
  final void Function(Map<String, dynamic>) onAdd;
  final void Function(int) onRemove;
  final void Function(int) onDelete;
  final Future<void> Function() onCompleteSale;
  final bool showAppBar;
  final VoidCallback? onBrowseProducts;
  final VoidCallback? onCartChanged;
  final String? initialMessage;
  final bool initialMessageSuccess;

  const CartPage({
    super.key,
    required this.cart,
    required this.onAdd,
    required this.onRemove,
    required this.onDelete,
    required this.onCompleteSale,
    this.showAppBar = false,
    this.onBrowseProducts,
    this.onCartChanged,
    this.initialMessage,
    this.initialMessageSuccess = true,
  });

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  final TextEditingController _cashCtrl = TextEditingController();
  final Set<int> _selectedCartIndexes = <int>{};
  bool _completing = false;

  @override
  void initState() {
    super.initState();
    final message = widget.initialMessage;
    if (message != null && message.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showBanner(message, success: widget.initialMessageSuccess);
      });
    }
  }

  OverlayEntry? _messageOverlay;
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _pageSurface => _isDark ? const Color(0xFF0F172A) : _surface;
  Color get _panelSurface => _isDark ? const Color(0xFF111827) : _cardBg;
  Color get _mutedSurface => _isDark ? const Color(0xFF1E293B) : _surface;
  Color get _lineColor => _isDark ? const Color(0xFF253047) : _border;
  Color get _primaryText => _isDark ? const Color(0xFFF8FAFC) : _textPrimary;
  Color get _secondaryText =>
      _isDark ? const Color(0xFFCBD5E1) : _textSecondary;
  Color get _tertiaryText => _isDark ? const Color(0xFF94A3B8) : _textTertiary;

  // ── Computed ───────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _cart => widget.cart;

  double get _total => _cart.fold(
    0.0,
    (s, i) => s + (i['product']['price'] as num) * (i['quantity'] as int),
  );

  int get _totalUnits => _cart.fold(0, (s, i) => s + (i['quantity'] as int));
  bool get _isSelectingCartItems => _selectedCartIndexes.isNotEmpty;

  void _notifyCartChanged() => widget.onCartChanged?.call();

  // ── Helpers ────────────────────────────────────────────────────────────────
  Widget _buildImage(String? path, {double size = 48}) {
    if (path == null || path.isEmpty) return _placeholder(size);
    final file = File(path);
    if (file.existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _placeholder(size),
        ),
      );
    }
    return _placeholder(size);
  }

  void _showBanner(String message, {bool success = false}) {
    _messageOverlay?.remove();

    _messageOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 14,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: MessageBanner(message: message, success: success),
        ),
      ),
    );

    Overlay.of(context).insert(_messageOverlay!);

    Future.delayed(const Duration(seconds: 2), () {
      _messageOverlay?.remove();
      _messageOverlay = null;
    });
  }

  Widget _placeholder(double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: _purpleBg,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _purpleBorder, width: 0.5),
    ),
    child: Icon(
      Icons.image_not_supported_outlined,
      size: size * 0.42,
      color: _purple,
    ),
  );

  List<double> _quickCashOptions(double total) {
    if (total <= 0) return [];

    final options = <double>[total];

    void addRounded(double step) {
      final amount = (total / step).ceil() * step;
      final alreadyAdded = options.any(
        (option) => (option - amount).abs() < 0.01,
      );
      if (amount >= total && !alreadyAdded) {
        options.add(amount);
      }
    }

    for (final step in const [50.0, 100.0, 200.0, 500.0, 1000.0]) {
      addRounded(step);
      if (options.length == 4) break;
    }

    var next = options.isEmpty ? (total / 50).ceil() * 50.0 : options.last + 50;
    while (options.length < 4) {
      final alreadyAdded = options.any(
        (option) => (option - next).abs() < 0.01,
      );
      if (!alreadyAdded) options.add(next);
      next += 50;
    }

    return options.take(4).toList();
  }

  String _cashInputTextForAmount(double amount) {
    if (amount == amount.roundToDouble()) {
      return amount.toStringAsFixed(0);
    }
    return amount.toStringAsFixed(2);
  }

  String _sanitizeMoneyInput(String value) {
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

  double _cashAmount() {
    final sanitized = _sanitizeMoneyInput(_cashCtrl.text);
    if (sanitized.isEmpty || sanitized == '.') return 0;
    return double.tryParse(sanitized) ?? 0;
  }

  int _moneyCents(double value) => (value * 100).round();

  double _centsToMoney(int cents) => cents / 100;

  TextEditingValue _formatMoneyEdit(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final sanitized = _sanitizeMoneyInput(newValue.text);
    if (sanitized == newValue.text) return newValue;

    return TextEditingValue(
      text: sanitized,
      selection: TextSelection.collapsed(offset: sanitized.length),
    );
  }

  String _sanitizeQuantityInput(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';

    final stripped = digits.replaceFirst(RegExp(r'^0+'), '');
    return stripped.isEmpty ? '0' : stripped;
  }

  int? _parseQuantityInput(String value, int maxQuantity) {
    final sanitized = _sanitizeQuantityInput(value);
    final parsed = int.tryParse(sanitized);
    if (parsed == null || parsed < 1 || parsed > maxQuantity) return null;
    return parsed;
  }

  TextEditingValue _formatQuantityEdit(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final sanitized = _sanitizeQuantityInput(newValue.text);
    if (sanitized == newValue.text) return newValue;

    return TextEditingValue(
      text: sanitized,
      selection: TextSelection.collapsed(offset: sanitized.length),
    );
  }

  void _clearCart() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Clear cart?',
          style: TextStyle(fontWeight: FontWeight.w700, color: _textPrimary),
        ),
        content: const Text(
          'All items will be removed from the cart.',
          style: TextStyle(color: _textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: _textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                for (final item in _cart) {
                  item['product']['stock'] += item['quantity'];
                }
                _cart.clear();
                _selectedCartIndexes.clear();
              });
              _notifyCartChanged();
            },
            child: const Text(
              'Clear',
              style: TextStyle(color: _red, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // ── Payment sheet ──────────────────────────────────────────────────────────
  void _toggleCartItemSelection(int index) {
    if (index < 0 || index >= _cart.length) return;

    setState(() {
      if (_selectedCartIndexes.contains(index)) {
        _selectedCartIndexes.remove(index);
      } else {
        _selectedCartIndexes.add(index);
      }
    });
  }

  void _startCartItemSelection(int index) {
    HapticFeedback.mediumImpact();
    _toggleCartItemSelection(index);
  }

  Future<void> _deleteSelectedCartItems() async {
    final selected =
        _selectedCartIndexes
            .where((index) => index >= 0 && index < _cart.length)
            .toList()
          ..sort((a, b) => b.compareTo(a));

    if (selected.isEmpty) {
      setState(_selectedCartIndexes.clear);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _panelSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            'Remove selected?',
            style: TextStyle(
              color: _primaryText,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            'Remove ${selected.length} selected product${selected.length == 1 ? '' : 's'} from the cart?',
            style: TextStyle(color: _secondaryText),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('Cancel', style: TextStyle(color: _secondaryText)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _red,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    for (final index in selected) {
      if (index >= 0 && index < _cart.length) {
        widget.onDelete(index);
      }
    }

    setState(_selectedCartIndexes.clear);
    _notifyCartChanged();
  }

  void _handleSummaryDelete() {
    if (_isSelectingCartItems) {
      _deleteSelectedCartItems();
    } else {
      _clearCart();
    }
  }

  Future<bool> _confirmCompleteSale({
    required double cashAmount,
    required double change,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        final panel = isDark ? const Color(0xFF111827) : Colors.white;
        final primaryText = isDark ? const Color(0xFFF8FAFC) : _textPrimary;
        final secondaryText = isDark ? const Color(0xFFCBD5E1) : _textSecondary;
        final line = isDark ? const Color(0xFF253047) : _border;
        final successText = isDark ? const Color(0xFF86EFAC) : _green;

        return AlertDialog(
          backgroundColor: panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Complete sale?',
            style: TextStyle(color: primaryText, fontWeight: FontWeight.w800),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Please confirm before saving this sale.',
                style: TextStyle(color: secondaryText),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _mutedSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: line, width: 0.5),
                ),
                child: Column(
                  children: [
                    _ConfirmRow(
                      label: 'Total',
                      value: CurrencyFormatter.format(_total),
                    ),
                    const SizedBox(height: 8),
                    _ConfirmRow(
                      label: 'Cash',
                      value: CurrencyFormatter.format(cashAmount),
                    ),
                    const SizedBox(height: 8),
                    _ConfirmRow(
                      label: 'Change',
                      value: CurrencyFormatter.format(change),
                      valueColor: successText,
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('Cancel', style: TextStyle(color: secondaryText)),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    return confirmed == true;
  }

  void _showPaymentSheet() {
    _cashCtrl.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) {
          final cashAmt = _cashAmount();
          final totalCents = _moneyCents(_total);
          final cashCents = _moneyCents(cashAmt);
          final changeCents = cashCents - totalCents;
          final change = _centsToMoney(changeCents);
          final amountNeeded = _centsToMoney(-changeCents);
          final sufficient = cashCents >= totalCents && cashCents > 0;
          final quickAmounts = _quickCashOptions(_total);
          final accentBg = _isDark
              ? _primary.withValues(alpha: 0.14)
              : _purpleBg;
          final accentBorder = _isDark
              ? _primary.withValues(alpha: 0.32)
              : _purpleBorder;
          final accentFg = _isDark ? const Color(0xFFC4B5FD) : _purple;
          final successFg = _isDark ? const Color(0xFF86EFAC) : _green;
          final dangerFg = _isDark ? const Color(0xFFFCA5A5) : _red;
          final cashFieldBg = _isDark
              ? const Color(0xFF1E293B)
              : const Color(0xFFF8F9FF);
          final cashFieldBorder = sufficient
              ? _primary.withValues(alpha: _isDark ? 0.65 : 0.4)
              : _lineColor;
          final statusBg = sufficient
              ? (_isDark ? _green.withValues(alpha: 0.16) : _greenBg)
              : (_isDark ? _red.withValues(alpha: 0.16) : _redBg);
          final statusBorder = sufficient
              ? (_isDark ? _green.withValues(alpha: 0.34) : _greenBorder)
              : (_isDark ? _red.withValues(alpha: 0.34) : _redBorder);
          final disabledButtonBg = _isDark
              ? const Color(0xFF253047)
              : Colors.grey[200];

          final media = MediaQuery.of(ctx);
          final keyboardInset = media.viewInsets.bottom;
          final systemNavInset = media.padding.bottom;

          return Padding(
            padding: EdgeInsets.only(bottom: keyboardInset),
            child: Container(
              decoration: BoxDecoration(
                color: _panelSurface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              padding: EdgeInsets.fromLTRB(16, 0, 16, systemNavInset + 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 14),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _lineColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Sheet header
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: accentBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: accentBorder, width: 0.5),
                        ),
                        child: Icon(
                          Icons.payments_outlined,
                          size: 18,
                          color: accentFg,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cash payment',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: _primaryText,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Enter cash received',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: _secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: accentBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: accentBorder, width: 0.5),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Total price',
                          style: TextStyle(
                            color: _secondaryText,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          CurrencyFormatter.format(_total),
                          style: TextStyle(
                            color: accentFg,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Cash input + change
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                    decoration: BoxDecoration(
                      color: cashFieldBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cashFieldBorder),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                    child: Row(
                      children: [
                        Text(
                          '₱ ',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: _primary,
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _cashCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              TextInputFormatter.withFunction(
                                _formatMoneyEdit,
                              ),
                            ],
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              color: _primaryText,
                            ),
                            decoration: InputDecoration(
                              hintText: '0.00',
                              hintStyle: TextStyle(
                                color: _tertiaryText,
                                fontSize: 19,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 9,
                              ),
                            ),
                            onChanged: (v) => setModal(() {}),
                          ),
                        ),
                      ],
                    ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          height: 54,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: cashAmt > 0 ? statusBg : _mutedSurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: cashAmt > 0 ? statusBorder : _lineColor,
                              width: 0.5,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cashAmt <= 0
                                    ? 'Change'
                                    : sufficient
                                    ? 'Change'
                                    : 'Amount needed',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: cashAmt <= 0
                                      ? _secondaryText
                                      : sufficient
                                      ? successFg
                                      : dangerFg,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                cashAmt <= 0
                                    ? CurrencyFormatter.format(0)
                                    : sufficient
                                    ? CurrencyFormatter.format(change)
                                    : CurrencyFormatter.format(amountNeeded),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: cashAmt <= 0
                                      ? _primaryText
                                      : sufficient
                                      ? successFg
                                      : dangerFg,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Quick amounts
                  Row(
                    children: quickAmounts.asMap().entries.map((entry) {
                      final i = entry.key;
                      final amt = entry.value;
                      final cashText = _cashInputTextForAmount(amt);
                      final isSelected =
                          _sanitizeMoneyInput(_cashCtrl.text) == cashText;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: i == 0 ? 0 : 3,
                            right: i == quickAmounts.length - 1 ? 0 : 3,
                          ),
                          child: GestureDetector(
                            onTap: () {
                              _cashCtrl.text = _sanitizeMoneyInput(cashText);
                              _cashCtrl.selection = TextSelection.collapsed(
                                offset: _cashCtrl.text.length,
                              );
                              setModal(() {});
                            },
                            child: Container(
                              height: 34,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isSelected ? _primary : accentBg,
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(
                                  color: isSelected ? _primary : accentBorder,
                                  width: 0.5,
                                ),
                              ),
                              child: Text(
                                i == 0
                                    ? CurrencyFormatter.format(amt)
                                    : '₱${amt.toStringAsFixed(0)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected ? Colors.white : accentFg,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 14),

                  // Confirm button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: sufficient && !_completing
                          ? () async {
                              final confirmed = await _confirmCompleteSale(
                                cashAmount: cashAmt,
                                change: change,
                              );
                              if (!confirmed) return;
                              if (!mounted || !ctx.mounted) return;
                              setModal(() {});
                              setState(() => _completing = true);
                              Navigator.pop(ctx);
                              try {
                                await widget.onCompleteSale();
                              } catch (e) {
                                if (!mounted) return;
                                _showBanner('Error: $e', success: false);
                              } finally {
                                if (mounted) {
                                  setState(() => _completing = false);
                                }
                              }
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        disabledBackgroundColor: disabledButtonBg,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _completing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.check_circle_outline_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  sufficient
                                      ? 'Confirm sale'
                                      : cashAmt > 0
                                      ? 'Need ${CurrencyFormatter.format(amountNeeded)} more'
                                      : 'Enter cash received',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageSurface,
      appBar: widget.showAppBar ? _buildAppBar() : null,
      body: _cart.isEmpty ? _buildEmpty() : _buildCartBody(),
      bottomNavigationBar: _cart.isEmpty ? null : _buildBottomBar(),
    );
  }

  // ── App bar ────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _panelSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _mutedSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _lineColor, width: 0.5),
          ),
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 16,
            color: _primaryText,
          ),
        ),
      ),
      title: Column(
        children: [
          Text(
            'Shopping cart',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _primaryText,
              letterSpacing: -0.3,
            ),
          ),
          if (_cart.isNotEmpty)
            Text(
              '$_totalUnits item${_totalUnits != 1 ? 's' : ''}',
              style: TextStyle(
                fontSize: 11,
                color: _secondaryText,
                fontWeight: FontWeight.w400,
              ),
            ),
        ],
      ),
      actions: [
        if (_cart.isNotEmpty)
          GestureDetector(
            onTap: _clearCart,
            child: Container(
              margin: const EdgeInsets.all(10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _redBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _redBorder, width: 0.5),
              ),
              child: const Text(
                'Clear all',
                style: TextStyle(
                  color: _red,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ),
      ],
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(0.5),
        child: Divider(height: 0.5, thickness: 0.5, color: _lineColor),
      ),
    );
  }

  // ── Cart body ──────────────────────────────────────────────────────────────
  Widget _buildCartBody() {
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _CartSummaryHeaderDelegate(
              backgroundColor: _pageSurface,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isSelectingCartItems ? 'Selected' : 'Checkout',
                          style: TextStyle(
                            color: _primaryText,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isSelectingCartItems
                              ? '${_selectedCartIndexes.length} product${_selectedCartIndexes.length != 1 ? 's' : ''}'
                              : '$_totalUnits item${_totalUnits != 1 ? 's' : ''}',
                          style: TextStyle(
                            color: _secondaryText,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _handleSummaryDelete,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: _isDark ? _red.withValues(alpha: 0.18) : _redBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isDark
                              ? _red.withValues(alpha: 0.34)
                              : _redBorder,
                          width: 0.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        size: 22,
                        color: _red,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Item list
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 120),
            sliver: SliverList.separated(
              itemCount: _cart.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _buildCartItem(i),
            ),
          ),
        ],
      ),
    );
  }

  // ── Cart item ──────────────────────────────────────────────────────────────
  Widget _buildCartItem(int i) {
    final item = _cart[i];
    final product = item['product'];
    final String name = product['title'] as String? ?? '';
    final double price = (product['price'] as num).toDouble();
    final int quantity = item['quantity'] as int;
    final double discount = (item['discount'] as num?)?.toDouble() ?? 0;
    final double itemTotal = (price * quantity) - discount;
    final String? path = product['imagePath'] as String?;
    final isSelected = _selectedCartIndexes.contains(i);

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        if (_isSelectingCartItems) {
          _toggleCartItemSelection(i);
        } else {
          _showCartItemSheet(i);
        }
      },
      onLongPress: () => _startCartItemSelection(i),
      child: Container(
        constraints: const BoxConstraints(minHeight: 86),
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: isSelected
              ? (_isDark ? _purple.withValues(alpha: 0.18) : _purpleBg)
              : _panelSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? _purpleBorder : _lineColor,
            width: isSelected ? 1 : 0.5,
          ),
        ),
        child: Row(
          children: [
            if (_isSelectingCartItems) ...[
              Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: isSelected ? _purple : _tertiaryText,
                size: 20,
              ),
              const SizedBox(width: 8),
            ],
            _buildImage(path, size: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _primaryText,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$quantity x ${CurrencyFormatter.format(price)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _secondaryText,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    discount > 0
                        ? '- ${CurrencyFormatter.format(discount)} discount'
                        : 'No discount',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _tertiaryText, fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  CurrencyFormatter.format(itemTotal),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _primaryText,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _isDark
                        ? _purple.withValues(alpha: 0.18)
                        : _purpleBg,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.edit_outlined,
                    size: 15,
                    color: _purple,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────
  void _showCartItemSheet(int index) {
    if (index < 0 || index >= _cart.length) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            if (index >= _cart.length) {
              Navigator.pop(sheetContext);
              return const SizedBox.shrink();
            }

            final item = _cart[index];
            final product = item['product'] as Map<String, dynamic>;

            final name = product['title'] as String? ?? '';
            final category = product['category'] as String? ?? '';
            final price = (product['price'] as num).toDouble();
            final quantity = item['quantity'] as int;
            final stock = (product['stock'] as num?)?.toInt() ?? 0;
            final imagePath = product['imagePath'] as String?;
            final subtotal = price * quantity;

            void refreshSheet() {
              if (!mounted) return;

              setState(() {});
              _notifyCartChanged();

              if (index >= _cart.length) {
                Navigator.pop(sheetContext);
                return;
              }

              setSheetState(() {});
            }

            Future<void> showQuantityInput() async {
              final maxQuantity = quantity + stock;
              final controller = TextEditingController();

              void closeQuantityDialog(
                BuildContext dialogContext, [
                int? value,
              ]) {
                FocusScope.of(dialogContext).unfocus();
                Navigator.of(dialogContext, rootNavigator: true).pop(value);
              }

              final nextQuantity = await showDialog<int>(
                context: context,
                builder: (dialogContext) {
                  String? errorText;

                  return StatefulBuilder(
                    builder: (context, setDialogState) {
                      return AlertDialog(
                        backgroundColor: _panelSurface,
                        insetPadding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 24,
                        ),
                        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                        contentPadding: const EdgeInsets.fromLTRB(
                          20,
                          12,
                          20,
                          4,
                        ),
                        actionsPadding: const EdgeInsets.fromLTRB(
                          16,
                          8,
                          16,
                          14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        title: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Enter quantity',
                              style: TextStyle(
                                color: _primaryText,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Available up to $maxQuantity',
                              style: TextStyle(
                                color: _secondaryText,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        content: TextField(
                          controller: controller,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            TextInputFormatter.withFunction(
                              _formatQuantityEdit,
                            ),
                          ],
                          style: TextStyle(
                            color: _primaryText,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            hintText: '0',
                            errorText: errorText,
                            isDense: true,
                            filled: true,
                            fillColor: _mutedSurface,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: _lineColor,
                                width: 0.5,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: _lineColor,
                                width: 0.5,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: _primary,
                                width: 1.2,
                              ),
                            ),
                          ),
                          onSubmitted: (_) {
                            final parsed = _parseQuantityInput(
                              controller.text,
                              maxQuantity,
                            );
                            if (parsed == null) {
                              setDialogState(() {
                                errorText = 'Enter 1 to $maxQuantity';
                              });
                              return;
                            }

                            closeQuantityDialog(dialogContext, parsed);
                          },
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => closeQuantityDialog(dialogContext),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(82, 42),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'Cancel',
                              style: TextStyle(color: _secondaryText),
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              final parsed = _parseQuantityInput(
                                controller.text,
                                maxQuantity,
                              );
                              if (parsed == null) {
                                setDialogState(() {
                                  errorText = 'Enter 1 to $maxQuantity';
                                });
                                return;
                              }

                              closeQuantityDialog(dialogContext, parsed);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primary,
                              minimumSize: const Size(92, 42),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Update',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              );

              if (nextQuantity == null ||
                  nextQuantity == quantity ||
                  index >= _cart.length) {
                return;
              }

              HapticFeedback.lightImpact();

              if (nextQuantity > quantity) {
                for (var i = 0; i < nextQuantity - quantity; i++) {
                  widget.onAdd(product);
                }
              } else {
                for (var i = 0; i < quantity - nextQuantity; i++) {
                  widget.onRemove(index);
                }
              }

              refreshSheet();
            }

            return SafeArea(
              top: false,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.88,
                ),
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                decoration: BoxDecoration(
                  color: _panelSurface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(top: 8, bottom: 10),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: _lineColor,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),

                      Text(
                        'Update Quantity',
                        style: TextStyle(
                          color: _primaryText,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),

                      const SizedBox(height: 18),

                      Row(
                        children: [
                          _buildImage(imagePath, size: 58),
                          const SizedBox(width: 12),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _primaryText,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),

                                if (category.isNotEmpty)
                                  Text(
                                    category,
                                    style: TextStyle(
                                      color: _secondaryText,
                                      fontSize: 12,
                                    ),
                                  ),

                                const SizedBox(height: 4),

                                Text(
                                  CurrencyFormatter.format(price),
                                  style: const TextStyle(
                                    color: _purple,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      _CartSheetField(
                        label: 'Selling Price',
                        value: CurrencyFormatter.format(price),
                        icon: Icons.sell_outlined,
                      ),

                      const SizedBox(height: 12),

                      _CartSheetField(
                        label: 'Quantity',
                        icon: Icons.format_list_numbered_rounded,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _CartSheetQtyButton(
                              icon: Icons.remove_rounded,
                              onTap: () {
                                HapticFeedback.lightImpact();
                                widget.onRemove(index);
                                refreshSheet();
                              },
                            ),

                            GestureDetector(
                              onTap: showQuantityInput,
                              child: Container(
                                width: 54,
                                height: 34,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _mutedSurface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: _lineColor,
                                    width: 0.5,
                                  ),
                                ),
                                child: Text(
                                  '$quantity',
                                  style: TextStyle(
                                    color: _primaryText,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),

                            _CartSheetQtyButton(
                              icon: Icons.add_rounded,
                              enabled: stock > 0,
                              filled: true,
                              onTap: () {
                                HapticFeedback.lightImpact();
                                widget.onAdd(product);
                                refreshSheet();
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      _CartSheetField(
                        label: 'Total Price',
                        value: CurrencyFormatter.format(subtotal),
                        icon: Icons.receipt_long_outlined,
                        valueColor: _purple,
                      ),

                      const SizedBox(height: 8),

                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          stock > 0 ? '$stock more available' : 'No more stock',
                          style: TextStyle(color: _tertiaryText, fontSize: 12),
                        ),
                      ),

                      const SizedBox(height: 18),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primary,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Done',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmpty() {
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: _purpleBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_cart_outlined,
                size: 38,
                color: _purple,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Cart is empty',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _primaryText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add products to get started',
              style: TextStyle(fontSize: 13, color: _secondaryText),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: widget.onBrowseProducts ?? () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Browse products',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Bottom bar ─────────────────────────────────────────────────────────────
  Widget _buildBottomBar() {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(8, 0, 8, 14),
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _panelSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _lineColor, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _isDark ? 0.24 : 0.08),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            SizedBox(
              width: 68,
              child: _BottomMetric(
                label: 'Total Items',
                value: '$_totalUnits',
                valueColor: _primaryText,
              ),
            ),
            Container(
              width: 1,
              height: 38,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: _lineColor,
            ),
            Expanded(
              child: _BottomMetric(
                label: 'Grand Total',
                value: CurrencyFormatter.format(_total),
                valueColor: _purple,
                alignCenter: true,
              ),
            ),
            Container(
              width: 1,
              height: 38,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: _lineColor,
            ),
            SizedBox(
              width: 120,
              height: 46,
              child: ElevatedButton(
                onPressed: _completing ? null : _showPaymentSheet,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  disabledBackgroundColor: Colors.grey[300],
                  elevation: 6,
                  shadowColor: _primary.withValues(alpha: 0.28),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _completing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.credit_card_outlined,
                            color: Colors.white,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Pay now',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Summary card ─────────────────────────────────────────────────────────────
class _BottomMetric extends StatelessWidget {
  const _BottomMetric({
    required this.label,
    required this.value,
    required this.valueColor,
    this.alignCenter = false,
  });

  final String label;
  final String value;
  final Color valueColor;
  final bool alignCenter;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark ? const Color(0xFFCBD5E1) : _textSecondary;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: alignCenter
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignCenter ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: labelColor,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignCenter ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: valueColor,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark ? const Color(0xFFCBD5E1) : _textSecondary;
    final textColor =
        valueColor ?? (isDark ? const Color(0xFFF8FAFC) : _textPrimary);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: labelColor)),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: textColor,
          ),
        ),
      ],
    );
  }
}

class _CartSheetField extends StatelessWidget {
  const _CartSheetField({
    required this.label,
    required this.icon,
    this.value,
    this.valueColor,
    this.trailing,
  });

  final String label;
  final IconData icon;
  final String? value;
  final Color? valueColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? const Color(0xFFF8FAFC) : _textPrimary;
    final secondaryText = isDark ? const Color(0xFFCBD5E1) : _textSecondary;
    final mutedSurface = isDark ? const Color(0xFF1E293B) : _surface;
    final lineColor = isDark ? const Color(0xFF253047) : _border;

    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: mutedSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: lineColor, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: secondaryText),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: secondaryText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          trailing ??
              Text(
                value ?? '',
                style: TextStyle(
                  color: valueColor ?? primaryText,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
        ],
      ),
    );
  }
}

class _CartSheetQtyButton extends StatelessWidget {
  const _CartSheetQtyButton({
    required this.icon,
    required this.onTap,
    this.enabled = true,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = filled
        ? Colors.white
        : isDark
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF1A1F36);

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: filled ? _primary : Colors.transparent,
            shape: BoxShape.circle,
            border: filled ? null : Border.all(color: _border, width: 0.5),
          ),
          child: Icon(icon, color: fg, size: 18),
        ),
      ),
    );
  }
}

class _CartSummaryHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _CartSummaryHeaderDelegate({
    required this.backgroundColor,
    required this.child,
  });

  final Color backgroundColor;
  final Widget child;

  static const double _height = 58;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        boxShadow: overlapsContent
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _CartSummaryHeaderDelegate oldDelegate) {
    return oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.child != child;
  }
}

// ─── Stepper button ───────────────────────────────────────────────────────────
