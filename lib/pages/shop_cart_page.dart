import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_app/database/database_helper.dart';
import 'package:pos_app/theme/app_typography.dart';
import 'package:pos_app/utils/currency.dart';
import 'package:pos_app/utils/message_banner.dart';
import 'package:pos_app/utils/product_discount.dart';
import 'package:pos_app/utils/receipt_discount.dart';
import 'recent_sales.dart';

// Design tokens
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
const _red = Color(0xFFA32D2D);
const _redBg = Color(0xFFFCEBEB);
const _redBorder = Color(0xFFF7C1C1);

// CartPage
class SaleCompletion {
  const SaleCompletion({required this.saleId, required this.receiptNumber});

  final int saleId;
  final String receiptNumber;
}

class CartPage extends StatefulWidget {
  final List<Map<String, dynamic>> cart;
  final void Function(Map<String, dynamic>) onAdd;
  final void Function(int) onRemove;
  final void Function(int) onDelete;
  final Future<SaleCompletion?> Function(ReceiptDiscount discount)
  onCompleteSale;
  final String currentUsername;
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
    required this.currentUsername,
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
  final TextEditingController _discountCtrl = TextEditingController();
  final Set<int> _selectedCartIndexes = <int>{};
  ReceiptDiscountType _discountType = ReceiptDiscountType.amount;
  String _selectedDiscountName = 'No Discount';
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

  @override
  void dispose() {
    _cashCtrl.dispose();
    _discountCtrl.dispose();
    _messageOverlay?.remove();
    super.dispose();
  }

  // Computed
  List<Map<String, dynamic>> get _cart => widget.cart;

  double get _subtotal => _cart.fold(
    0.0,
    (s, i) => s + discountedCartItemPrice(i) * (i['quantity'] as int),
  );

  ReceiptDiscount get _receiptDiscount => ReceiptDiscount(
    type: _discountType,
    value: double.tryParse(_sanitizeMoneyInput(_discountCtrl.text)) ?? 0,
  );

  double get _discountAmount => _receiptDiscount.amountFor(_subtotal);

  double get _total =>
      _centsToMoney(_moneyCents(_subtotal) - _moneyCents(_discountAmount));

  int get _totalUnits => _cart.fold(0, (s, i) => s + (i['quantity'] as int));
  bool get _isSelectingCartItems => _selectedCartIndexes.isNotEmpty;
  bool get _hasReceiptDiscount => _discountAmount > 0;
  String get _discountSummary {
    if (!_hasReceiptDiscount) return 'No Discount';
    if (_selectedDiscountName == 'Custom Discount') {
      final value =
          double.tryParse(_sanitizeMoneyInput(_discountCtrl.text)) ?? 0;
      if (_discountType == ReceiptDiscountType.percent) {
        return 'Custom (${value.toStringAsFixed(value % 1 == 0 ? 0 : 2)}%)';
      }
      return 'Custom (${CurrencyFormatter.format(_discountAmount)})';
    }
    if (_discountType == ReceiptDiscountType.percent) {
      final value =
          double.tryParse(_sanitizeMoneyInput(_discountCtrl.text)) ?? 0;
      return '$_selectedDiscountName (${_formatDiscountPercent(value)}%)';
    }
    return _selectedDiscountName;
  }

  double get _productDiscountAmount =>
      _cart.fold<double>(0, (sum, item) => sum + cartItemDiscountAmount(item));

  void _notifyCartChanged() => widget.onCartChanged?.call();

  // Helpers
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
      builder: (context) => success
          ? Positioned.fill(
              child: IgnorePointer(
                child: Center(child: CenteredToastLabel(message: message)),
              ),
            )
          : Positioned(
              top: MediaQuery.of(context).padding.top + 14,
              left: 16,
              right: 16,
              child: Material(
                color: Colors.transparent,
                child: MessageBanner(message: message),
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

  String _formatDiscountPercent(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }

  IconData _discountIcon(String name) {
    final normalized = name.toLowerCase();
    if (normalized.contains('senior')) return Icons.person_rounded;
    if (normalized.contains('pwd')) return Icons.accessible_forward_rounded;
    if (normalized.contains('employee')) return Icons.person_pin_rounded;
    if (normalized.contains('promo')) return Icons.local_offer_rounded;
    return Icons.sell_rounded;
  }

  Color _discountIconColor(String name) {
    final normalized = name.toLowerCase();
    if (normalized.contains('senior')) return const Color(0xFF6DB34F);
    if (normalized.contains('pwd')) return const Color(0xFF1E88E5);
    if (normalized.contains('employee')) return const Color(0xFFFF981F);
    if (normalized.contains('promo')) return const Color(0xFF6D3FE5);
    return _green;
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

  void _clearReceiptDiscount({void Function()? setModal}) {
    _selectedDiscountName = 'No Discount';
    _discountType = ReceiptDiscountType.amount;
    _discountCtrl.clear();
    setState(() {});
    setModal?.call();
  }

  void _applyReceiptDiscount({
    required String name,
    required ReceiptDiscountType type,
    required double value,
    void Function()? setModal,
  }) {
    _selectedDiscountName = name;
    _discountType = type;
    _discountCtrl.text = _cashInputTextForAmount(value);
    _discountCtrl.selection = TextSelection.collapsed(
      offset: _discountCtrl.text.length,
    );
    setState(() {});
    setModal?.call();
  }

  Future<void> _showDiscountSelector({
    void Function()? refreshPaymentSheet,
  }) async {
    final options = await DatabaseHelper.instance.getReceiptDiscounts();
    if (!mounted) return;
    final customCtrl = TextEditingController(
      text: _selectedDiscountName == 'Custom Discount'
          ? _discountCtrl.text
          : '',
    );
    var selectedName = _hasReceiptDiscount
        ? _selectedDiscountName
        : 'No Discount';
    var customType = _selectedDiscountName == 'Custom Discount'
        ? _discountType
        : ReceiptDiscountType.amount;

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final media = MediaQuery.of(context);
          final inset = media.viewInsets.bottom;
          final selectedIsCustom = selectedName == 'Custom Discount';

          void applySelected() {
            if (selectedName == 'No Discount') {
              _clearReceiptDiscount(setModal: refreshPaymentSheet);
              Navigator.pop(sheetContext);
              return;
            }

            if (selectedIsCustom) {
              final value =
                  double.tryParse(_sanitizeMoneyInput(customCtrl.text)) ?? 0;
              if (value <= 0) {
                _clearReceiptDiscount(setModal: refreshPaymentSheet);
              } else {
                _applyReceiptDiscount(
                  name: 'Custom Discount',
                  type: customType,
                  value: value,
                  setModal: refreshPaymentSheet,
                );
              }
              Navigator.pop(sheetContext);
              return;
            }

            final preset = options.firstWhere(
              (option) => option.name == selectedName,
              orElse: () => options.first,
            );
            _applyReceiptDiscount(
              name: preset.name,
              type: ReceiptDiscountType.percent,
              value: preset.percent,
              setModal: refreshPaymentSheet,
            );
            Navigator.pop(sheetContext);
          }

          return Padding(
            padding: EdgeInsets.only(bottom: inset),
            child: Container(
              constraints: BoxConstraints(maxHeight: media.size.height * 0.82),
              decoration: BoxDecoration(
                color: _panelSurface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                16,
                10,
                16,
                media.padding.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _lineColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Select Discount',
                    style: TextStyle(
                      color: _primaryText,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Column(
                        children: [
                          _DiscountOptionRow(
                            name: 'No Discount',
                            selected: selectedName == 'No Discount',
                            icon: Icons.local_offer_rounded,
                            iconColor: _textTertiary,
                            trailing: '',
                            onTap: () => setSheetState(() {
                              selectedName = 'No Discount';
                            }),
                          ),
                          for (final option in options)
                            _DiscountOptionRow(
                              name:
                                  '${option.name} (${_formatDiscountPercent(option.percent)}%)',
                              selected: selectedName == option.name,
                              icon: _discountIcon(option.name),
                              iconColor: _discountIconColor(option.name),
                              trailing: '${option.percent.toStringAsFixed(0)}%',
                              onTap: () => setSheetState(() {
                                selectedName = option.name;
                              }),
                            ),
                          _DiscountOptionRow(
                            name: 'Custom Discount',
                            selected: selectedIsCustom,
                            icon: Icons.percent_rounded,
                            iconColor: const Color(0xFFE83E6F),
                            trailing: '',
                            onTap: () => setSheetState(() {
                              selectedName = 'Custom Discount';
                            }),
                          ),
                          if (selectedIsCustom) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                _DiscountTypeButton(
                                  label: 'Amount',
                                  selected:
                                      customType == ReceiptDiscountType.amount,
                                  onTap: () => setSheetState(() {
                                    customType = ReceiptDiscountType.amount;
                                  }),
                                ),
                                const SizedBox(width: 8),
                                _DiscountTypeButton(
                                  label: 'Percent',
                                  selected:
                                      customType == ReceiptDiscountType.percent,
                                  onTap: () => setSheetState(() {
                                    customType = ReceiptDiscountType.percent;
                                  }),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: customCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                TextInputFormatter.withFunction(
                                  _formatMoneyEdit,
                                ),
                              ],
                              decoration: InputDecoration(
                                isDense: true,
                                labelText:
                                    customType == ReceiptDiscountType.amount
                                    ? 'Discount amount'
                                    : 'Discount percent',
                                prefixText:
                                    customType == ReceiptDiscountType.amount
                                    ? 'PHP '
                                    : null,
                                suffixText:
                                    customType == ReceiptDiscountType.percent
                                    ? '%'
                                    : null,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            side: BorderSide(color: _lineColor),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: _primaryText,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: applySelected,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            backgroundColor: _green,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Apply',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
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
    ).whenComplete(customCtrl.dispose);
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

  // Payment sheet
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

  void _handleCheckoutBack() {
    if (_isSelectingCartItems) {
      setState(_selectedCartIndexes.clear);
      return;
    }

    if (widget.onBrowseProducts != null) {
      widget.onBrowseProducts!.call();
      return;
    }

    Navigator.maybePop(context);
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

  Future<void> _showSaleSuccessSheet({
    required double total,
    required SaleCompletion completion,
  }) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        final panelBg = isDark ? const Color(0xFF111827) : Colors.white;
        final headerBg = isDark
            ? const Color(0xFF052E16)
            : const Color(0xFFF0FDF4);
        final checkBg = isDark
            ? const Color(0xFF16A34A)
            : const Color(0xFF15803D);
        final titleClr = isDark
            ? const Color(0xFF86EFAC)
            : const Color(0xFF15803D);
        final pillBg = isDark
            ? const Color(0xFF1E293B)
            : const Color(0xFFF1F5F9);
        final pillText = isDark
            ? const Color(0xFF94A3B8)
            : const Color(0xFF475569);
        final pillAccent = isDark
            ? const Color(0xFF4ADE80)
            : const Color(0xFF16A34A);
        final btnBg = isDark
            ? const Color(0xFFF8FAFC)
            : const Color(0xFF0F172A);
        final btnFg = isDark
            ? const Color(0xFF0F172A)
            : const Color(0xFFF8FAFC);

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 24,
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 300),
            decoration: BoxDecoration(
              color: panelBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            clipBehavior: Clip.hardEdge,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  color: headerBg,
                  padding: const EdgeInsets.fromLTRB(24, 34, 24, 28),
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: checkBg,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Sale Completed!',
                        textAlign: TextAlign.center,
                        style: AppTypography.pageTitle.copyWith(
                          color: titleClr,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'The transaction was successful.',
                        textAlign: TextAlign.center,
                        style: AppTypography.label.copyWith(
                          color: titleClr.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _SaleStatusPill(
                        icon: Icons.payments_outlined,
                        label: 'Total amount',
                        value: CurrencyFormatter.format(total),
                        bg: pillBg,
                        labelColor: pillText,
                        valueColor: pillAccent,
                      ),
                      const SizedBox(height: 8),
                      _SaleStatusPill(
                        icon: Icons.receipt_long_outlined,
                        label: 'Receipt number',
                        value: completion.receiptNumber,
                        bg: pillBg,
                        labelColor: pillText,
                        valueColor: pillText,
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RecentSalesPage(
                                  saleId: completion.saleId,
                                  currentUsername: widget.currentUsername,
                                ),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: btnBg,
                            side: BorderSide(color: btnBg, width: 1.2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(
                            Icons.receipt_long_outlined,
                            size: 16,
                          ),
                          label: Text(
                            'View receipt',
                            style: AppTypography.button,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            widget.onBrowseProducts?.call();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: btnBg,
                            foregroundColor: btnFg,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(
                            Icons.add_circle_outline_rounded,
                            size: 16,
                          ),
                          label: Text('New sale', style: AppTypography.button),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _completeSaleFromPayment({
    required double cashAmount,
    required double change,
    required double total,
    required ReceiptDiscount discount,
    VoidCallback? onConfirmed,
  }) async {
    if (_completing || !mounted) return;

    final confirmed = await _confirmCompleteSale(
      cashAmount: cashAmount,
      change: change,
    );
    if (!confirmed || !mounted) return;

    onConfirmed?.call();
    if (!mounted) return;

    setState(() => _completing = true);
    try {
      final completion = await widget.onCompleteSale(discount);
      if (!mounted || completion == null) return;
      _selectedDiscountName = 'No Discount';
      _discountType = ReceiptDiscountType.amount;
      _discountCtrl.clear();
      await _showSaleSuccessSheet(total: total, completion: completion);
    } catch (e) {
      if (!mounted) return;
      _showBanner('Error: $e', success: false);
    } finally {
      if (mounted) {
        setState(() => _completing = false);
      }
    }
  }

  void _showPaymentSheet() {
    if (_completing || _cart.isEmpty) return;
    _cashCtrl.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;

          // Surface tokens
          final panelBg = isDark ? const Color(0xFF111827) : Colors.white;
          final mutedBg = isDark
              ? const Color(0xFF1E293B)
              : const Color(0xFFF4F5FF);
          final fieldBg = isDark ? const Color(0xFF111827) : Colors.white;
          final lineFaint = isDark
              ? const Color(0xFF253047)
              : const Color(0xFFEEEEEE);

          // Text tokens
          final textPri = isDark
              ? const Color(0xFFF8FAFC)
              : const Color(0xFF1A1F36);
          final textSec = isDark
              ? const Color(0xFFCBD5E1)
              : const Color(0xFF6B7280);
          final textTer = isDark
              ? const Color(0xFF94A3B8)
              : const Color(0xFFAAAAAA);

          // Accent tokens
          final accentFg = isDark
              ? const Color(0xFFC4B5FD)
              : const Color(0xFF534AB7);
          final accentBg = isDark
              ? _primary.withValues(alpha: 0.14)
              : const Color(0xFFEEEDFE);
          final accentBorder = isDark
              ? _primary.withValues(alpha: 0.32)
              : const Color(0xFFCECBF6);

          // Semantic tokens
          final successFg = isDark
              ? const Color(0xFF86EFAC)
              : const Color(0xFF3B6D11);
          final dangerFg = isDark
              ? const Color(0xFFFCA5A5)
              : const Color(0xFFA32D2D);

          // Computed values
          final cashAmt = _cashAmount();
          final subtotal = _subtotal;
          final productDisc = _productDiscountAmount;
          final receiptDisc = _discountAmount;
          final totalCents = _moneyCents(_total);
          final cashCents = _moneyCents(cashAmt);
          final changeCents = cashCents - totalCents;
          final change = _centsToMoney(changeCents);
          final needed = _centsToMoney(-changeCents);
          final sufficient = cashCents >= totalCents && cashCents > 0;
          final quickAmts = _quickCashOptions(_total);

          final media = MediaQuery.of(ctx);
          final keyboardInset = media.viewInsets.bottom;
          final navInset = media.padding.bottom;
          final maxHeight = (media.size.height - keyboardInset).clamp(
            0.0,
            640.0,
          );

          return Padding(
            padding: EdgeInsets.only(bottom: keyboardInset),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Container(
                decoration: BoxDecoration(
                  color: panelBg,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Drag handle ──────────────────────────────
                    Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(top: 12, bottom: 4),
                      decoration: BoxDecoration(
                        color: lineFaint,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),

                    Flexible(
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.fromLTRB(16, 8, 16, navInset + 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Header row ───────────────────────
                            _PaySheetHeader(
                              accentFg: accentFg,
                              accentBg: accentBg,
                              accentBorder: accentBorder,
                              fieldBg: fieldBg,
                              lineFaint: lineFaint,
                              textPri: textPri,
                              textSec: textSec,
                              onBack: () => Navigator.pop(ctx),
                            ),

                            const SizedBox(height: 12),

                            // ── Payment summary ──────────────────
                            _PaymentSummaryCard(
                              items: _totalUnits,
                              subtotal: subtotal,
                              productDiscount: productDisc,
                              receiptDiscount: receiptDisc,
                              receiptDiscountLabel: _discountSummary,
                              total: _total,
                              accentFg: accentFg,
                              accentBg: accentBg,
                              mutedSurface: mutedBg,
                              lineColor: lineFaint,
                              primaryText: textPri,
                              secondaryText: textSec,
                              dangerFg: dangerFg,
                              onDiscountTap: () => _showDiscountSelector(
                                refreshPaymentSheet: () => setModal(() {}),
                              ),
                              onClearDiscount: () => _clearReceiptDiscount(
                                setModal: () => setModal(() {}),
                              ),
                            ),

                            const SizedBox(height: 14),

                            // ── Section label ────────────────────
                            Row(
                              children: [
                                Expanded(
                                  child: _PaymentFieldLabel(
                                    text: 'Cash received',
                                    color: accentFg,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _PaymentFieldLabel(
                                    text: cashAmt > 0 && !sufficient
                                        ? 'Still needed'
                                        : 'Change',
                                    color: accentFg,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 8),

                            // ── Cash input + Change ──────────────
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Cash field
                                  Expanded(
                                    child: _CashInputField(
                                      controller: _cashCtrl,
                                      fieldBg: fieldBg,
                                      accentFg: accentFg,
                                      accentBorder: accentBorder,
                                      textPri: textPri,
                                      textTer: textTer,
                                      lineFaint: lineFaint,
                                      sufficient: sufficient,
                                      onChanged: (_) => setModal(() {}),
                                      formatMoneyEdit: _formatMoneyEdit,
                                    ),
                                  ),

                                  const SizedBox(width: 10),

                                  // Change / needed field
                                  Expanded(
                                    child: _ChangeDisplay(
                                      cashAmt: cashAmt,
                                      sufficient: sufficient,
                                      change: change,
                                      needed: needed,
                                      mutedBg: mutedBg,
                                      lineFaint: lineFaint,
                                      textSec: textSec,
                                      successFg: successFg,
                                      dangerFg: dangerFg,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 10),

                            // ── Quick-amount pills ───────────────
                            Row(
                              children: quickAmts.asMap().entries.map((e) {
                                final i = e.key;
                                final amt = e.value;
                                final cashText = _cashInputTextForAmount(amt);
                                final isExact =
                                    _sanitizeMoneyInput(_cashCtrl.text) ==
                                    cashText;
                                return Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      left: i == 0 ? 0 : 3,
                                      right: i == quickAmts.length - 1 ? 0 : 3,
                                    ),
                                    child: _QuickAmountPill(
                                      label: i == 0
                                          ? CurrencyFormatter.format(amt)
                                          : 'PHP ${amt.toStringAsFixed(0)}',
                                      isSelected: isExact,
                                      accentBg: accentBg,
                                      accentBorder: accentBorder,
                                      accentFg: accentFg,
                                      onTap: () {
                                        _cashCtrl.text = cashText;
                                        _cashCtrl.selection =
                                            TextSelection.collapsed(
                                              offset: _cashCtrl.text.length,
                                            );
                                        setModal(() {});
                                      },
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),

                            const SizedBox(height: 14),
                          ],
                        ),
                      ),
                    ),

                    // ── Confirm button ───────────────────────────
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, navInset + 16),
                      child: _ConfirmSaleButton(
                        sufficient: sufficient,
                        completing: _completing,
                        cashAmt: cashAmt,
                        change: change,
                        needed: needed,
                        total: _total,
                        onConfirm: () async {
                          final total = _total;
                          final discount = _receiptDiscount;
                          await _completeSaleFromPayment(
                            cashAmount: cashAmt,
                            change: change,
                            total: total,
                            discount: discount,
                            onConfirmed: () => Navigator.pop(ctx),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Build
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageSurface,
      appBar: widget.showAppBar ? _buildAppBar() : null,
      body: _cart.isEmpty ? _buildEmpty() : _buildCartBody(),
      bottomNavigationBar: _cart.isEmpty ? null : _buildBottomBar(),
    );
  }

  // App bar
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
              fontSize: 14,
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

  // Cart body
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
                  GestureDetector(
                    onTap: _handleCheckoutBack,
                    child: Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _mutedSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _lineColor, width: 0.5),
                      ),
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 18,
                        color: _primaryText,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          _isSelectingCartItems ? 'Selected' : 'Checkout',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _primaryText,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (_isSelectingCartItems) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${_selectedCartIndexes.length} product${_selectedCartIndexes.length != 1 ? 's' : ''}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _secondaryText,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _handleSummaryDelete,
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      size: 24,
                      color: Colors.black,
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

  // Cart item
  Widget _buildCartItem(int i) {
    final item = _cart[i];
    final product = item['product'];
    final String name = product['title'] as String? ?? '';
    final double price = (product['price'] as num).toDouble();
    final double salePrice = discountedCartItemPrice(item);
    final double discountPercent = cartItemDiscountPercent(item);
    final int quantity = item['quantity'] as int;
    final double discount = cartItemDiscountAmount(item);
    final double itemTotal = salePrice * quantity;
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
                  discountPercent > 0
                      ? Row(
                          children: [
                            Flexible(
                              child: Text(
                                '$quantity x ${CurrencyFormatter.format(salePrice)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _secondaryText,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                CurrencyFormatter.format(price),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _tertiaryText,
                                  fontSize: 10,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Text(
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
                        ? '- ${CurrencyFormatter.format(discount)} product discount'
                        : 'No discount',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _tertiaryText, fontSize: 11),
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

  // Empty state
  void _showCartItemSheet(int index) {
    if (index < 0 || index >= _cart.length) return;

    final initialDiscountPercent = cartItemDiscountPercent(_cart[index]);
    final discountCtrl = TextEditingController(
      text: initialDiscountPercent > 0
          ? _cashInputTextForAmount(initialDiscountPercent)
          : '',
    );

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
            final salePrice = discountedCartItemPrice(item);
            final discountPercent = cartItemDiscountPercent(item);
            final quantity = item['quantity'] as int;
            final productDiscount = cartItemDiscountAmount(item);
            final stock = (product['stock'] as num?)?.toInt() ?? 0;
            final imagePath = product['imagePath'] as String?;
            final subtotal = salePrice * quantity;
            final discountInput =
                double.tryParse(_sanitizeMoneyInput(discountCtrl.text)) ?? 0;
            final discountInputInvalid =
                discountCtrl.text.trim().isNotEmpty &&
                (discountInput <= 0 || discountInput >= 100);

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
                                fontSize: 16,
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
                                  CurrencyFormatter.format(salePrice),
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
                      if (discountPercent > 0) ...[
                        const SizedBox(height: 8),
                        _CartSheetField(
                          label: 'Product Discount',
                          value:
                              '${discountPercent.toStringAsFixed(discountPercent % 1 == 0 ? 0 : 2)}% off',
                          icon: Icons.local_offer_outlined,
                          valueColor: _red,
                        ),
                        const SizedBox(height: 8),
                        _CartSheetField(
                          label: 'Sale Price',
                          value: CurrencyFormatter.format(salePrice),
                          icon: Icons.price_check_outlined,
                          valueColor: _green,
                        ),
                        const SizedBox(height: 8),
                        _CartSheetField(
                          label: 'You Save',
                          value: CurrencyFormatter.format(productDiscount),
                          icon: Icons.savings_outlined,
                          valueColor: _red,
                        ),
                      ],

                      const SizedBox(height: 12),

                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _mutedSurface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _lineColor, width: 0.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: _red.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: const Icon(
                                    Icons.local_offer_outlined,
                                    color: _red,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Checkout discount',
                                        style: TextStyle(
                                          color: _primaryText,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Applies only to this cart item',
                                        style: TextStyle(
                                          color: _secondaryText,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch.adaptive(
                                  value:
                                      discountPercent > 0 ||
                                      item['checkout_discount_enabled'] == true,
                                  activeThumbColor: _primary,
                                  onChanged: (enabled) {
                                    if (enabled) {
                                      final fallback = productDiscountPercent(
                                        product,
                                      );
                                      final percent =
                                          discountInput > 0 &&
                                              discountInput < 100
                                          ? discountInput
                                          : fallback > 0
                                          ? fallback
                                          : 10.0;
                                      discountCtrl.text =
                                          _cashInputTextForAmount(percent);
                                      item['checkout_discount_enabled'] = true;
                                      item['checkout_discount_percent'] =
                                          percent;
                                    } else {
                                      item['checkout_discount_enabled'] = false;
                                      item['checkout_discount_percent'] = null;
                                      discountCtrl.clear();
                                    }
                                    refreshSheet();
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: discountCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                TextInputFormatter.withFunction(
                                  _formatMoneyEdit,
                                ),
                              ],
                              style: TextStyle(
                                color: _primaryText,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: 'Percent off',
                                suffixText: '%',
                                errorText: discountInputInvalid
                                    ? 'Enter more than 0 and less than 100'
                                    : null,
                                filled: true,
                                fillColor: _panelSurface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onChanged: (value) {
                                final percent =
                                    double.tryParse(
                                      _sanitizeMoneyInput(value),
                                    ) ??
                                    0;
                                if (percent > 0 && percent < 100) {
                                  item['checkout_discount_enabled'] = true;
                                  item['checkout_discount_percent'] = percent;
                                } else {
                                  item['checkout_discount_enabled'] = false;
                                  item['checkout_discount_percent'] = null;
                                }
                                refreshSheet();
                              },
                            ),
                          ],
                        ),
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
                              fontSize: 14,
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
    ).whenComplete(discountCtrl.dispose);
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

  // Bottom bar
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
                  padding: EdgeInsets.zero,
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
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.credit_card_outlined,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Pay now',
                                maxLines: 1,
                                style: AppTypography.button.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaySheetHeader extends StatelessWidget {
  const _PaySheetHeader({
    required this.accentFg,
    required this.accentBg,
    required this.accentBorder,
    required this.fieldBg,
    required this.lineFaint,
    required this.textPri,
    required this.textSec,
    required this.onBack,
  });

  final Color accentFg, accentBg, accentBorder, fieldBg, lineFaint, textPri;
  final Color textSec;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Back button
        GestureDetector(
          onTap: onBack,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: fieldBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: lineFaint, width: 0.5),
            ),
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 16,
              color: accentFg,
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Icon badge
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: accentBg,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: accentBorder, width: 0.5),
          ),
          child: Icon(Icons.payments_outlined, size: 20, color: accentFg),
        ),
        const SizedBox(width: 12),

        // Title + subtitle
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cash payment',
                style: AppTypography.cardTitle.copyWith(color: textPri),
              ),
              const SizedBox(height: 2),
              Text(
                'Enter cash received',
                style: AppTypography.caption.copyWith(color: textSec),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CashInputField extends StatelessWidget {
  const _CashInputField({
    required this.controller,
    required this.fieldBg,
    required this.accentFg,
    required this.accentBorder,
    required this.textPri,
    required this.textTer,
    required this.lineFaint,
    required this.sufficient,
    required this.onChanged,
    required this.formatMoneyEdit,
  });

  final TextEditingController controller;
  final Color fieldBg, accentFg, accentBorder, textPri, textTer, lineFaint;
  final bool sufficient;
  final ValueChanged<String> onChanged;
  final TextEditingValue Function(TextEditingValue, TextEditingValue)
  formatMoneyEdit;

  @override
  Widget build(BuildContext context) {
    final activeBorder = sufficient
        ? _primary.withValues(alpha: 0.6)
        : accentBorder;

    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: fieldBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: controller.text.isEmpty ? lineFaint : activeBorder,
          width: controller.text.isEmpty ? 0.5 : 1.5,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'PHP',
            style: AppTypography.label.copyWith(
              color: accentFg,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                TextInputFormatter.withFunction(formatMoneyEdit),
              ],
              style: AppTypography.total.copyWith(color: textPri),
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: AppTypography.total.copyWith(
                  color: textTer,
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangeDisplay extends StatelessWidget {
  const _ChangeDisplay({
    required this.cashAmt,
    required this.sufficient,
    required this.change,
    required this.needed,
    required this.mutedBg,
    required this.lineFaint,
    required this.textSec,
    required this.successFg,
    required this.dangerFg,
  });

  final double cashAmt, change, needed;
  final bool sufficient;
  final Color mutedBg, lineFaint, textSec, successFg, dangerFg;

  String get _value {
    if (cashAmt <= 0) return '—';
    if (sufficient) return CurrencyFormatter.format(change);
    return '−${CurrencyFormatter.format(needed)}';
  }

  Color _valueColor(Color fallback) {
    if (cashAmt <= 0) return fallback;
    if (!sufficient) return dangerFg;
    return successFg;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: mutedBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: lineFaint, width: 0.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.centerLeft,
      child: Text(
        _value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.total.copyWith(color: _valueColor(textSec)),
      ),
    );
  }
}

class _PaymentFieldLabel extends StatelessWidget {
  const _PaymentFieldLabel({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.label.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _QuickAmountPill extends StatelessWidget {
  const _QuickAmountPill({
    required this.label,
    required this.isSelected,
    required this.accentBg,
    required this.accentBorder,
    required this.accentFg,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final Color accentBg, accentBorder, accentFg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 38,
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
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.helperText.copyWith(
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : accentFg,
          ),
        ),
      ),
    );
  }
}

class _ConfirmSaleButton extends StatelessWidget {
  const _ConfirmSaleButton({
    required this.sufficient,
    required this.completing,
    required this.cashAmt,
    required this.change,
    required this.needed,
    required this.total,
    required this.onConfirm,
  });

  final bool sufficient, completing;
  final double cashAmt, change, needed, total;
  final VoidCallback onConfirm;

  String get _label {
    if (completing) return '';
    if (cashAmt <= 0) return 'Enter cash received';
    if (!sufficient) return 'Need ${CurrencyFormatter.format(needed)} more';
    if (change == 0) return 'Confirm sale';
    return 'Confirm sale';
  }

  @override
  Widget build(BuildContext context) {
    final active = sufficient && !completing;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: active ? onConfirm : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          disabledBackgroundColor: Colors.grey[200],
          elevation: active ? 4 : 0,
          shadowColor: _primary.withValues(alpha: 0.28),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: completing
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
                  Flexible(
                    child: Text(
                      _label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.button.copyWith(
                        color: active ? Colors.white : Colors.grey[500],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// Summary card
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
          style: AppTypography.helperText.copyWith(
            color: labelColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignCenter ? TextAlign.center : TextAlign.start,
          style: AppTypography.price.copyWith(color: valueColor),
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
        Text(label, style: AppTypography.label.copyWith(color: labelColor)),
        Text(value, style: AppTypography.button.copyWith(color: textColor)),
      ],
    );
  }
}

class _PaymentSummaryCard extends StatelessWidget {
  const _PaymentSummaryCard({
    required this.items,
    required this.subtotal,
    required this.productDiscount,
    required this.receiptDiscount,
    required this.receiptDiscountLabel,
    required this.total,
    required this.accentFg,
    required this.accentBg,
    required this.mutedSurface,
    required this.lineColor,
    required this.primaryText,
    required this.secondaryText,
    required this.dangerFg,
    required this.onDiscountTap,
    required this.onClearDiscount,
  });

  final VoidCallback onDiscountTap;
  final VoidCallback onClearDiscount;
  final int items;
  final double subtotal;
  final double productDiscount;
  final double receiptDiscount;
  final String receiptDiscountLabel;
  final double total;
  final Color accentFg;
  final Color accentBg;
  final Color mutedSurface;
  final Color lineColor;
  final Color primaryText;
  final Color secondaryText;
  final Color dangerFg;

  String get _discountBadgeText {
    final match = RegExp(r'\(([^)]+%)\)').firstMatch(receiptDiscountLabel);
    final percent = match?.group(1);
    return percent == null ? 'APPLIED' : '$percent OFF';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: mutedSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: lineColor, width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _SummaryIcon(
                icon: Icons.receipt_long_outlined,
                bg: accentBg,
                fg: accentFg,
              ),
              const SizedBox(width: 12),
              Text(
                'Payment summary',
                style: AppTypography.button.copyWith(
                  color: accentFg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Divider(height: 16, color: lineColor),

          _PaymentSummaryLine(
            icon: Icons.shopping_bag_outlined,
            iconBg: accentBg,
            iconColor: accentFg,
            label: 'Items',
            value: '$items',
            labelColor: secondaryText,
            valueColor: primaryText,
          ),
          const SizedBox(height: 7),

          _PaymentSummaryLine(
            icon: Icons.receipt_long_outlined,
            iconBg: accentBg,
            iconColor: accentFg,
            label: 'Subtotal',
            value: CurrencyFormatter.format(subtotal),
            labelColor: secondaryText,
            valueColor: primaryText,
          ),

          if (productDiscount > 0) ...[
            const SizedBox(height: 7),
            _PaymentSummaryLine(
              icon: Icons.local_offer_outlined,
              iconBg: accentBg,
              iconColor: accentFg,
              label: 'Product discount',
              value: '-${CurrencyFormatter.format(productDiscount)}',
              labelColor: secondaryText,
              valueColor: dangerFg,
            ),
          ],

          if (receiptDiscount > 0) ...[
            const SizedBox(height: 7),
            _PaymentSummaryLine(
              icon: Icons.percent_rounded,
              iconBg: accentBg,
              iconColor: accentFg,
              label: 'Receipt discount',
              value: '-${CurrencyFormatter.format(receiptDiscount)}',
              labelColor: secondaryText,
              valueColor: dangerFg,
            ),
          ],

          Divider(height: 22, color: lineColor),

          Row(
            children: [
              Text(
                'Total',
                style: AppTypography.button.copyWith(
                  color: accentFg,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                CurrencyFormatter.format(total),
                style: AppTypography.total.copyWith(color: accentFg),
              ),
            ],
          ),
          const SizedBox(height: 10),

          OutlinedButton.icon(
            onPressed: onDiscountTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: accentFg,
              side: BorderSide(color: accentFg, width: 1.1),
              minimumSize: const Size.fromHeight(36),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
              ),
            ),
            icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
            label: Text(
              'Add Discount',
              style: AppTypography.label.copyWith(
                color: accentFg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (receiptDiscount > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF3FA34D),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Applied discount',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.label.copyWith(
                        color: Color(0xFF3FA34D),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDFF5DE),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      _discountBadgeText,
                      style: AppTypography.helperText.copyWith(
                        color: Color(0xFF3FA34D),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: onClearDiscount,
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFF8B95A5),
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryIcon extends StatelessWidget {
  const _SummaryIcon({required this.icon, required this.bg, required this.fg});

  final IconData icon;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, size: 14, color: fg),
    );
  }
}

class _PaymentSummaryLine extends StatelessWidget {
  const _PaymentSummaryLine({
    required this.label,
    required this.value,
    required this.labelColor,
    required this.valueColor,
    this.icon,
    this.iconBg,
    this.iconColor,
  });

  final String label;
  final String value;
  final Color labelColor;
  final Color valueColor;
  final IconData? icon;
  final Color? iconBg;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            _SummaryIcon(
              icon: icon!,
              bg: iconBg ?? Colors.transparent,
              fg: iconColor ?? labelColor,
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.label.copyWith(color: labelColor),
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 132),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: AppTypography.button.copyWith(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscountTypeButton extends StatelessWidget {
  const _DiscountTypeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? _primary : Colors.transparent,
          foregroundColor: selected ? Colors.white : _primary,
          side: BorderSide(color: selected ? _primary : _purpleBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
        child: Text(label),
      ),
    );
  }
}

class _DiscountOptionRow extends StatelessWidget {
  const _DiscountOptionRow({
    required this.name,
    required this.selected,
    required this.icon,
    required this.iconColor,
    required this.trailing,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final IconData icon;
  final Color iconColor;
  final String trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? const Color(0xFFF8FAFC) : _textPrimary;
    final secondaryText = isDark ? const Color(0xFFCBD5E1) : _textSecondary;
    final lineColor = isDark ? const Color(0xFF253047) : _border;
    final selectedColor = isDark ? const Color(0xFF86EFAC) : _green;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: lineColor, width: 0.5)),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? selectedColor : secondaryText,
              size: 24,
            ),
            const SizedBox(width: 12),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: primaryText,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (trailing.isNotEmpty)
              Text(
                trailing,
                style: TextStyle(
                  color: selectedColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SaleStatusPill extends StatelessWidget {
  const _SaleStatusPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.bg,
    required this.labelColor,
    required this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color bg;
  final Color labelColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: labelColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.label.copyWith(color: labelColor),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: AppTypography.label.copyWith(
                color: valueColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
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

// Stepper button
