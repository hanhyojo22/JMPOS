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

    final options = <double>[];

    void addRounded(double step) {
      final amount = (total / step).ceil() * step;
      if (amount >= total && !options.contains(amount)) {
        options.add(amount);
      }
    }

    for (final step in const [50.0, 100.0, 200.0, 500.0, 1000.0]) {
      addRounded(step);
      if (options.length == 4) break;
    }

    var next = options.isEmpty ? (total / 50).ceil() * 50.0 : options.last + 50;
    while (options.length < 4) {
      if (!options.contains(next)) options.add(next);
      next += 50;
    }

    options.sort();
    return options.take(4).toList();
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
          final cashAmt = double.tryParse(_cashCtrl.text) ?? 0;
          final change = cashAmt - _total;
          final sufficient = cashAmt >= _total && cashAmt > 0;
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
                      margin: const EdgeInsets.only(top: 12, bottom: 18),
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
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: accentBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: accentBorder, width: 0.5),
                        ),
                        child: Icon(
                          Icons.payments_outlined,
                          size: 20,
                          color: accentFg,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cash payment',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: _primaryText,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
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
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          CurrencyFormatter.format(_total),
                          style: TextStyle(
                            color: accentFg,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Cash input
                  Container(
                    decoration: BoxDecoration(
                      color: cashFieldBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cashFieldBorder),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Text(
                          '₱ ',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
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
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d{0,2}'),
                              ),
                            ],
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: _primaryText,
                            ),
                            decoration: InputDecoration(
                              hintText: '0.00',
                              hintStyle: TextStyle(
                                color: _tertiaryText,
                                fontSize: 22,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 10,
                              ),
                            ),
                            onChanged: (v) => setModal(() {}),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Quick amounts
                  Row(
                    children: quickAmounts.asMap().entries.map((entry) {
                      final i = entry.key;
                      final amt = entry.value;
                      final isSelected =
                          _cashCtrl.text == amt.toStringAsFixed(0);
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: i == 0 ? 0 : 3,
                            right: i == quickAmounts.length - 1 ? 0 : 3,
                          ),
                          child: GestureDetector(
                            onTap: () {
                              _cashCtrl.text = amt.toStringAsFixed(0);
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
                                '₱${amt.toStringAsFixed(0)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? Colors.white : accentFg,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 12),

                  // Change / insufficient
                  if (cashAmt > 0) ...[
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: statusBorder, width: 0.5),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            sufficient
                                ? Icons.check_circle_outline_rounded
                                : Icons.error_outline_rounded,
                            color: sufficient ? successFg : dangerFg,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            sufficient ? 'Change' : 'Insufficient cash',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: sufficient ? successFg : dangerFg,
                            ),
                          ),
                          const Spacer(),
                          if (sufficient)
                            Text(
                              CurrencyFormatter.format(change),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: successFg,
                                letterSpacing: -0.5,
                              ),
                            ),
                          if (!sufficient)
                            Text(
                              'Need ${CurrencyFormatter.format(-change)} more',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: dangerFg,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ] else
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
                                  'Confirm sale',
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
                    child: _SummaryCard(label: 'Items', value: '$_totalUnits'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SummaryCard(
                      label: 'Products',
                      value: '${_cart.length}',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SummaryCard(
                      label: 'Total',
                      value: CurrencyFormatter.format(_total),
                      valueColor: _purple,
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
    final String cat = product['category'] as String? ?? '';
    final double price = (product['price'] as num).toDouble();
    final int quantity = item['quantity'] as int;
    final double itemTotal = price * quantity;
    final String? path = product['imagePath'] as String?;

    return Container(
      decoration: BoxDecoration(
        color: _panelSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _lineColor, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Top row: image + info + delete
            Row(
              children: [
                _buildImage(path),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _primaryText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (cat.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          cat,
                          style: TextStyle(fontSize: 10, color: _tertiaryText),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        CurrencyFormatter.format(itemTotal),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _primaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _showCartItemSheet(i);
                  },
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _purpleBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: _purpleBorder, width: 0.5),
                    ),
                    child: const Icon(
                      Icons.edit_note,
                      size: 17,
                      color: _purple,
                    ),
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
              final controller = TextEditingController(text: '$quantity');

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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        title: Text(
                          'Enter quantity',
                          style: TextStyle(
                            color: _primaryText,
                            fontSize: 2,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                        content: TextField(
                          controller: controller,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          style: TextStyle(
                            color: _primaryText,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Quantity',
                            helperText: 'Max $maxQuantity',
                            errorText: errorText,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onSubmitted: (_) {
                            final parsed = int.tryParse(controller.text);
                            if (parsed == null ||
                                parsed < 1 ||
                                parsed > maxQuantity) {
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
                            child: Text(
                              'Cancel',
                              style: TextStyle(color: _secondaryText),
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              final parsed = int.tryParse(controller.text);
                              if (parsed == null ||
                                  parsed < 1 ||
                                  parsed > maxQuantity) {
                                setDialogState(() {
                                  errorText = 'Enter 1 to $maxQuantity';
                                });
                                return;
                              }

                              closeQuantityDialog(dialogContext, parsed);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primary,
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
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
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
                                    fontSize: 18,
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
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 16),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: _completing ? null : _showPaymentSheet,
          style: ElevatedButton.styleFrom(
            backgroundColor: _primary,
            disabledBackgroundColor: Colors.grey[300],
            elevation: 8,
            shadowColor: _primary.withValues(alpha: 0.35),
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
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.credit_card_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Pay now',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ─── Summary card ─────────────────────────────────────────────────────────────
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    this.valueColor,
  });
  final String label, value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF253047) : const Color(0xFFEEEEEE),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFFAAAAAA),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color:
                  valueColor ??
                  (isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1A1F36)),
            ),
            overflow: TextOverflow.ellipsis,
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
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: mutedSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: lineColor, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: secondaryText),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: secondaryText,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          trailing ??
              Text(
                value ?? '',
                style: TextStyle(
                  color: valueColor ?? primaryText,
                  fontSize: 16,
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

  static const double _height = 84;

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
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
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
