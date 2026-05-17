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
  final String? initialMessage;
  final bool initialMessageSuccess;

  const CartPage({
    super.key,
    required this.cart,
    required this.onAdd,
    required this.onRemove,
    required this.onDelete,
    required this.onCompleteSale,
    this.showAppBar = true,
    this.onBrowseProducts,
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
    child: Icon(Icons.inventory_2_outlined, size: size * 0.42, color: _purple),
  );

  List<double> _quickCashOptions(double total) {
    final List<double> opts = [];
    for (final r in [1, 5, 10, 20, 50, 100, 200, 500, 1000]) {
      final rounded = (total / r).ceil() * r.toDouble();
      if (!opts.contains(rounded) && opts.length < 4) opts.add(rounded);
    }
    return opts;
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

  void _setCartQuantity(int index, int requestedQuantity) {
    if (index < 0 || index >= _cart.length) return;

    final item = _cart[index];
    final product = item['product'] as Map<String, dynamic>;
    final currentQuantity = item['quantity'] as int;
    final availableStock = (product['stock'] as num?)?.toInt() ?? 0;
    final maxQuantity = currentQuantity + availableStock;
    final nextQuantity = requestedQuantity.clamp(1, maxQuantity);

    setState(() {
      final delta = nextQuantity - currentQuantity;
      product['stock'] = availableStock - delta;
      item['quantity'] = nextQuantity;
    });

    if (requestedQuantity > maxQuantity) {
      _showBanner('Only $maxQuantity available');
    } else {
      _showBanner('Quantity updated', success: true);
    }
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
                      valueColor: _green,
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
                          color: _purpleBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _purpleBorder, width: 0.5),
                        ),
                        child: const Icon(
                          Icons.payments_outlined,
                          size: 20,
                          color: _purple,
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
                          Text(
                            'Amount due: ${CurrencyFormatter.format(_total)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: _secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Total banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: _primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total due',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.75),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              CurrencyFormatter.format(_total),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Icon(
                          Icons.receipt_long_outlined,
                          color: Colors.white.withValues(alpha: 0.35),
                          size: 32,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Cash input
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: sufficient
                            ? _primary.withValues(alpha: 0.4)
                            : const Color(0xFFE8EAF0),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        const Text(
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
                            decoration: const InputDecoration(
                              hintText: '0.00',
                              hintStyle: TextStyle(
                                color: _textTertiary,
                                fontSize: 22,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
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
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: quickAmounts.map((amt) {
                      final isSelected =
                          _cashCtrl.text == amt.toStringAsFixed(0);
                      return GestureDetector(
                        onTap: () {
                          _cashCtrl.text = amt.toStringAsFixed(0);
                          setModal(() {});
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected ? _primary : _purpleBg,
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color: isSelected ? _primary : _purpleBorder,
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            '₱${amt.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? Colors.white : _purple,
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
                        color: sufficient ? _greenBg : _redBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: sufficient ? _greenBorder : _redBorder,
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            sufficient
                                ? Icons.check_circle_outline_rounded
                                : Icons.error_outline_rounded,
                            color: sufficient ? _green : _red,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            sufficient ? 'Change' : 'Insufficient cash',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: sufficient ? _green : _red,
                            ),
                          ),
                          const Spacer(),
                          if (sufficient)
                            Text(
                              CurrencyFormatter.format(change),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: _green,
                                letterSpacing: -0.5,
                              ),
                            ),
                          if (!sufficient)
                            Text(
                              'Need ${CurrencyFormatter.format(-change)} more',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _red,
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
                        disabledBackgroundColor: Colors.grey[200],
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
              '${_cart.length} item${_cart.length != 1 ? 's' : ''}',
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
    return CustomScrollView(
      slivers: [
        // Summary strip
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: _SummaryCard(label: 'Items', value: '${_cart.length}'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryCard(label: 'Units', value: '$_totalUnits'),
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
    );
  }

  // ── Cart item ──────────────────────────────────────────────────────────────
  Widget _buildCartItem(int i) {
    final item = _cart[i];
    final product = item['product'];
    final String name = product['title'] as String? ?? '';
    final String cat = product['category'] as String? ?? '';
    final double price = (product['price'] as num).toDouble();
    final int qty = item['quantity'] as int;
    final String? path = product['imagePath'] as String?;
    final double subtotal = price * qty;

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
                        CurrencyFormatter.format(price),
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
                    setState(() => widget.onDelete(i));

                    _showBanner('$name removed from cart');
                  },
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: _redBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: _redBorder, width: 0.5),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      size: 15,
                      color: _red,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Bottom row: subtotal + stepper
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              decoration: BoxDecoration(
                color: _mutedSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _lineColor, width: 0.5),
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Subtotal',
                        style: TextStyle(fontSize: 10, color: _tertiaryText),
                      ),
                      Text(
                        CurrencyFormatter.format(subtotal),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _purple,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Stepper
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: _panelSurface,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: _lineColor, width: 0.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _StepBtn(
                          icon: Icons.remove,
                          filled: false,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() => widget.onRemove(i));

                            _showBanner('Quantity updated');
                          },
                        ),
                        SizedBox(
                          width: 44,
                          height: 30,
                          child: _CartQuantityField(
                            key: ValueKey('cart_qty_${product['id']}_$qty'),
                            quantity: qty,
                            onSubmit: (value, reset) {
                              final parsed = int.tryParse(value.trim());
                              if (parsed == null || parsed <= 0) {
                                reset();
                                _showBanner('Enter a valid quantity');
                                return;
                              }
                              HapticFeedback.lightImpact();
                              _setCartQuantity(i, parsed);
                            },
                          ),
                        ),
                        _StepBtn(
                          icon: Icons.add,
                          filled: true,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() => widget.onAdd(product));

                            _showBanner('$name added to cart', success: true);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────
  Widget _buildEmpty() {
    return Center(
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
    );
  }

  // ── Bottom bar ─────────────────────────────────────────────────────────────
  Widget _buildBottomBar() {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
        decoration: BoxDecoration(
          color: _panelSurface,
          border: Border(top: BorderSide(color: _lineColor, width: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Total row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total amount',
                  style: TextStyle(fontSize: 13, color: _secondaryText),
                ),
                Text(
                  CurrencyFormatter.format(_total),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _primaryText,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Pay button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _completing ? null : _showPaymentSheet,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  disabledBackgroundColor: Colors.grey[300],
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
          ],
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

// ─── Stepper button ───────────────────────────────────────────────────────────
class _CartQuantityField extends StatefulWidget {
  const _CartQuantityField({
    super.key,
    required this.quantity,
    required this.onSubmit,
  });

  final int quantity;
  final void Function(String value, VoidCallback reset) onSubmit;

  @override
  State<_CartQuantityField> createState() => _CartQuantityFieldState();
}

class _CartQuantityFieldState extends State<_CartQuantityField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.quantity}');
  }

  @override
  void didUpdateWidget(covariant _CartQuantityField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quantity != widget.quantity) {
      _reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reset() {
    _controller.text = '${widget.quantity}';
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: _primary,
      ),
      decoration: const InputDecoration(
        isDense: true,
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(horizontal: 2, vertical: 7),
      ),
      onFieldSubmitted: (value) => widget.onSubmit(value, _reset),
      onTapOutside: (_) {
        final parsed = int.tryParse(_controller.text.trim());
        if (parsed == null || parsed <= 0) _reset();
      },
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({
    required this.icon,
    required this.filled,
    required this.onTap,
  });
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: filled ? const Color(0xFF5C6BC0) : Colors.transparent,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: 14,
        color: filled
            ? Colors.white
            : Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFFF8FAFC)
            : const Color(0xFF1A1F36),
      ),
    ),
  );
}
