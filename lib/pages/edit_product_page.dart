import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pos_app/database/database_helper.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────
const _primary = Color(0xFF5C6BC0);
const _surface = Color(0xFFF5F6FA);
const _cardBg = Colors.white;
const _border = Color(0xFFEEEEEE);
const _textPrimary = Color(0xFF1A1F36);
const _textSecondary = Color(0xFF6B7280);
const _textTertiary = Color(0xFFAAAAAA);
const _purple = Color(0xFF534AB7);
const _purpleBg = Color(0xFFEEEDFE);
const _green = Color(0xFF3B6D11);
const _greenBg = Color(0xFFEAF3DE);
const _greenBorder = Color(0xFFC0DD97);
const _amber = Color(0xFF854F0B);
const _amberBg = Color(0xFFFAEEDA);
const _amberBorder = Color(0xFFFAC775);
const _red = Color(0xFFA32D2D);
const _redBg = Color(0xFFFCEBEB);
const _redBorder = Color(0xFFF7C1C1);

// ─── Status tone ──────────────────────────────────────────────────────────────
enum _Tone { green, amber, red }

Color _toneBg(_Tone t) {
  switch (t) {
    case _Tone.green:
      return _greenBg;
    case _Tone.amber:
      return _amberBg;
    case _Tone.red:
      return _redBg;
  }
}

Color _toneBorder(_Tone t) {
  switch (t) {
    case _Tone.green:
      return _greenBorder;
    case _Tone.amber:
      return _amberBorder;
    case _Tone.red:
      return _redBorder;
  }
}

Color _toneFg(_Tone t) {
  switch (t) {
    case _Tone.green:
      return _green;
    case _Tone.amber:
      return _amber;
    case _Tone.red:
      return _red;
  }
}

// ─── EditProductPage ──────────────────────────────────────────────────────────
class EditProductPage extends StatefulWidget {
  final Map<String, dynamic> product;
  final String? scannedBarcode;
  final VoidCallback? onSaved;
  final VoidCallback? onBarcodeHandled;

  const EditProductPage({
    super.key,
    required this.product,
    this.scannedBarcode,
    this.onSaved,
    this.onBarcodeHandled,
  });

  @override
  State<EditProductPage> createState() => _EditProductPageState();
}

class _EditProductPageState extends State<EditProductPage> {
  final _picker = ImagePicker();
  final _formKey = GlobalKey<FormState>();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  PersistentBottomSheetController? _photoSheet;

  late TextEditingController _nameCtrl;
  late TextEditingController _barcodeCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _costCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _stockCtrl;

  String? _category;
  String? _currentImagePath;
  XFile? _pickedImage;
  bool _saving = false;
  String? _topWarning;
  bool _topWarningIsError = true;

  static const _categories = [
    'Beverages',
    'Groceries',
    'Snacks',
    'Household',
    'Other',
  ];

  // ── Init / dispose ─────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameCtrl = TextEditingController(text: p['product_name'] ?? '');
    _barcodeCtrl = TextEditingController(text: p['barcode'] ?? '');
    _descCtrl = TextEditingController(text: p['description'] ?? '');
    _costCtrl = TextEditingController(
      text: (p['cost_price'] as num?)?.toStringAsFixed(2) ?? '0.00',
    );
    _priceCtrl = TextEditingController(
      text: (p['price'] as num?)?.toStringAsFixed(2) ?? '0.00',
    );
    _stockCtrl = TextEditingController(
      text: (p['stock_quantity'] as int?)?.toString() ?? '0',
    );
    _category = p['category'] as String?;
    _currentImagePath = p['image_url'] as String?;
    _applyScannedBarcode();
  }

  @override
  void didUpdateWidget(covariant EditProductPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scannedBarcode != null &&
        widget.scannedBarcode != oldWidget.scannedBarcode) {
      _applyScannedBarcode();
    }
  }

  void _applyScannedBarcode() {
    final barcode = widget.scannedBarcode;
    if (barcode == null || barcode.isEmpty) return;
    _barcodeCtrl.text = barcode;
    widget.onBarcodeHandled?.call();
  }

  @override
  void dispose() {
    _photoSheet?.close();
    _nameCtrl.dispose();
    _barcodeCtrl.dispose();
    _descCtrl.dispose();
    _costCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  // ── Computed ───────────────────────────────────────────────────────────────
  String? get _imagePath => _pickedImage?.path ?? _currentImagePath;

  double get _margin {
    final cost = double.tryParse(_costCtrl.text) ?? 0;
    final sell = double.tryParse(_priceCtrl.text) ?? 0;
    if (cost <= 0 || sell <= 0) return 0;
    return ((sell - cost) / cost) * 100;
  }

  double get _profit {
    final cost = double.tryParse(_costCtrl.text) ?? 0;
    final sell = double.tryParse(_priceCtrl.text) ?? 0;
    return sell - cost;
  }

  int get _stock => int.tryParse(_stockCtrl.text) ?? 0;

  _Tone get _marginTone {
    if (_margin < 0) return _Tone.red;
    if (_margin < 20) return _Tone.amber;
    return _Tone.green;
  }

  _Tone get _stockTone {
    if (_stock == 0) return _Tone.red;
    if (_stock <= 10) return _Tone.amber;
    return _Tone.green;
  }

  String get _stockLabel => _stock == 0
      ? 'Out of stock'
      : _stock <= 10
      ? 'Low stock'
      : 'In stock';

  // ── Image ──────────────────────────────────────────────────────────────────
  Future<void> _pickImage(ImageSource src) async {
    final img = await _picker.pickImage(
      source: src,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (img != null) setState(() => _pickedImage = img);
  }

  void _showImageSheet() {
    if (_photoSheet != null) {
      _photoSheet!.close();
      _photoSheet = null;
      return;
    }

    _photoSheet = _scaffoldKey.currentState?.showBottomSheet(
      backgroundColor: Colors.transparent,
      elevation: 0,
      enableDrag: true,
      (_) => _ImageSheet(
        hasImage: _imagePath != null,
        onGallery: () {
          _photoSheet?.close();
          _photoSheet = null;
          _pickImage(ImageSource.gallery);
        },
        onCamera: () {
          _photoSheet?.close();
          _photoSheet = null;
          _pickImage(ImageSource.camera);
        },
        onRemove: () {
          setState(() {
            _pickedImage = null;
            _currentImagePath = null;
          });
          _photoSheet?.close();
          _photoSheet = null;
        },
      ),
    );
    _photoSheet?.closed.whenComplete(() => _photoSheet = null);
  }

  // ── Save ───────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      _showTopWarning('Please fix the errors before saving');
      return;
    }

    final barcode = _barcodeCtrl.text.trim();
    final productId = widget.product['id'] as int;

    final duplicateBarcode = await DatabaseHelper.instance.barcodeExists(
      barcode,
      excludeProductId: productId,
    );
    if (duplicateBarcode) {
      _showTopWarning('Duplicate barcode found!');
      return;
    }

    setState(() => _saving = true);
    try {
      final updated = {
        'id': productId,
        'product_name': _nameCtrl.text.trim(),
        'barcode': barcode,
        'category': _category,
        'description': _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        'price': double.parse(_priceCtrl.text),
        'cost_price': double.parse(_costCtrl.text),
        'stock_quantity': int.parse(_stockCtrl.text),
        'image_url': _imagePath,
        'updated_at': DateTime.now().toIso8601String(),
      };
      final result = await DatabaseHelper.instance.updateProduct(updated);
      if (!mounted) return;
      setState(() => _saving = false);
      if (result > 0) {
        _showTopWarning('Product updated!', error: false);
        await Future.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        widget.onSaved?.call();
      } else {
        _showTopWarning('Failed to update');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showTopWarning('Error: $e');
    }
  }

  void _showTopWarning(String message, {bool error = true}) {
    if (!mounted) return;
    setState(() {
      _topWarning = message;
      _topWarningIsError = error;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted || _topWarning != message) return;
      setState(() => _topWarning = null);
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: isDark ? const Color(0xFF0F172A) : _surface,
      body: SafeArea(
        child: Stack(
          children: [
            Form(
              key: _formKey,
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                      children: [
                        _buildIdentityCard(),
                        const SizedBox(height: 10),
                        _buildStatsRow(),
                        const SizedBox(height: 10),
                        _buildDetailsSection(),
                        const SizedBox(height: 10),
                        _buildPricingSection(),
                        const SizedBox(height: 10),
                        _buildInventorySection(),
                      ],
                    ),
                  ),
                  _buildBottomBar(),
                ],
              ),
            ),
            if (_topWarning != null)
              Positioned(
                top: 8,
                left: 14,
                right: 14,
                child: _TopWarning(
                  message: _topWarning!,
                  error: _topWarningIsError,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Identity card ──────────────────────────────────────────────────────────
  Widget _buildIdentityCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final imageBg = _primary.withValues(alpha: isDark ? 0.12 : 0.07);

    return GestureDetector(
      onTap: _showImageSheet,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // Full-width image or placeholder
            SizedBox(
              width: double.infinity,
              height: MediaQuery.of(context).size.height * 0.20,
              child: _imagePath != null && File(_imagePath!).existsSync()
                  ? Image.file(File(_imagePath!), fit: BoxFit.cover)
                  : Container(
                      color: imageBg,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: _purple.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 30,
                              color: _purple,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Tap to add photo',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: _purple,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),

            // Camera badge — bottom right
            Positioned(
              bottom: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.camera_alt_outlined,
                      size: 14,
                      color: Colors.white,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'Change photo',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
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

  // ── Stats row ──────────────────────────────────────────────────────────────
  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Stock',
            value: '$_stock units',
            tone: _stockTone,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            label: 'Margin',
            value: '${_margin.toStringAsFixed(1)}%',
            tone: _marginTone,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            label: 'Profit/unit',
            value: '₱${_profit.toStringAsFixed(2)}',
            tone: _marginTone,
          ),
        ),
      ],
    );
  }

  // ── Details section ────────────────────────────────────────────────────────
  Widget _buildDetailsSection() {
    return _SectionCard(
      iconBg: _purpleBg,
      iconColor: _purple,
      icon: Icons.description_outlined,
      title: 'Product details',
      child: Column(
        children: [
          _Field(
            label: 'Product name',
            controller: _nameCtrl,
            icon: Icons.label_outline_rounded,
            hint: 'e.g. Coca Cola 500ml',
            onChanged: (_) => setState(() {}),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 10),
          _Field(
            label: 'Barcode / SKU',
            controller: _barcodeCtrl,
            icon: Icons.qr_code_rounded,
            hint: '8851234567890',

            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 10),
          _DropdownField(
            label: 'Category',
            value: _categories.contains(_category) ? _category : null,
            items: _categories,
            onChanged: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: 10),
          _Field(
            label: 'Description',
            controller: _descCtrl,
            icon: Icons.notes_rounded,
            hint: 'Optional product notes...',
            maxLines: 3,
            validator: (_) => null,
          ),
        ],
      ),
    );
  }

  // ── Pricing section ────────────────────────────────────────────────────────
  Widget _buildPricingSection() {
    return _SectionCard(
      iconBg: _greenBg,
      iconColor: _green,
      icon: Icons.payments_outlined,
      title: 'Pricing',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _Field(
                  label: 'Cost price',
                  controller: _costCtrl,
                  icon: Icons.south_rounded,
                  iconColor: _red,
                  prefix: '₱',
                  hint: '0.00',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (double.tryParse(v) == null) return 'Invalid';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Field(
                  label: 'Selling price',
                  controller: _priceCtrl,
                  icon: Icons.north_rounded,
                  iconColor: _green,
                  prefix: '₱',
                  hint: '0.00',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (double.tryParse(v) == null) return 'Invalid';
                    return null;
                  },
                ),
              ),
            ],
          ),
          if (_costCtrl.text.isNotEmpty && _priceCtrl.text.isNotEmpty) ...[
            const SizedBox(height: 10),
            _Banner(
              tone: _marginTone,
              icon: _margin >= 0
                  ? Icons.trending_up_rounded
                  : Icons.trending_down_rounded,
              main: 'Margin ${_margin.toStringAsFixed(1)}%',
              sub: _margin >= 20
                  ? 'Above recommended 20%'
                  : _margin >= 0
                  ? 'Below recommended 20%'
                  : 'Selling below cost',
              trailing: '₱${_profit.toStringAsFixed(2)} / item',
            ),
          ],
        ],
      ),
    );
  }

  // ── Inventory section ──────────────────────────────────────────────────────
  Widget _buildInventorySection() {
    return _SectionCard(
      iconBg: _amberBg,
      iconColor: _amber,
      icon: Icons.warehouse_outlined,
      title: 'Inventory',
      child: Column(
        children: [
          _Field(
            label: 'Stock quantity',
            controller: _stockCtrl,
            icon: Icons.layers_outlined,
            hint: '0',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            suffix: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _toneBg(_stockTone),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: _toneBorder(_stockTone), width: 0.5),
              ),
              child: Text(
                _stockLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _toneFg(_stockTone),
                ),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Required';
              if (int.tryParse(v) == null) return 'Invalid';
              return null;
            },
          ),
          if (_stockCtrl.text.isNotEmpty) ...[
            const SizedBox(height: 10),
            _Banner(
              tone: _stockTone,
              icon: _stock == 0
                  ? Icons.remove_shopping_cart_outlined
                  : _stock <= 10
                  ? Icons.warning_amber_rounded
                  : Icons.check_circle_outline_rounded,
              main: _stockLabel,
              sub: '$_stock units available',
            ),
          ],
        ],
      ),
    );
  }

  // ── Bottom bar ─────────────────────────────────────────────────────────────
  Widget _buildBottomBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panel = isDark ? const Color(0xFF111827) : _cardBg;
    final line = isDark ? const Color(0xFF253047) : _border;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
      decoration: BoxDecoration(
        color: panel,
        border: Border(top: BorderSide(color: line, width: 0.5)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: _primary,
            disabledBackgroundColor: Colors.grey[300],
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _saving
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
                    Icon(Icons.save_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Save changes',
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

class _TopWarning extends StatelessWidget {
  const _TopWarning({required this.message, required this.error});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? const Color(0xFFDC2626) : const Color(0xFF22C55E);
    final icon = error ? Icons.error_outline : Icons.check_circle_rounded;

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── _StatCard ────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.tone,
  });
  final String label, value;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panel = isDark ? const Color(0xFF111827) : _cardBg;
    final line = isDark ? const Color(0xFF253047) : _border;
    final labelColor = isDark ? const Color(0xFF94A3B8) : _textTertiary;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: line, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: labelColor)),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _toneFg(tone),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─── _SectionCard ─────────────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.iconBg,
    required this.iconColor,
    required this.icon,
    required this.title,
    required this.child,
  });
  final Color iconBg, iconColor;
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panel = isDark ? const Color(0xFF111827) : _cardBg;
    final line = isDark ? const Color(0xFF253047) : _border;
    final text = isDark ? const Color(0xFFF8FAFC) : _textPrimary;

    return Container(
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: line, width: 0.5)),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: iconColor),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: text,
                  ),
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(14), child: child),
        ],
      ),
    );
  }
}

// ─── _Field ───────────────────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.icon,
    required this.hint,
    this.iconColor,
    this.prefix,
    this.suffix,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
    this.validator,
    this.onChanged,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final String hint;
  final Color? iconColor;
  final String? prefix;
  final Widget? suffix;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8F9FF);
    final line = isDark ? const Color(0xFF253047) : _border;
    final primaryText = isDark ? const Color(0xFFF8FAFC) : _textPrimary;
    final secondaryText = isDark ? const Color(0xFFCBD5E1) : _textSecondary;
    final tertiaryText = isDark ? const Color(0xFF94A3B8) : _textTertiary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: secondaryText,
          ),
        ),
        const SizedBox(height: 5),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          onChanged: onChanged,
          maxLines: maxLines,
          style: TextStyle(
            fontSize: 14,
            color: primaryText,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(fontSize: 14, color: tertiaryText),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Icon(icon, size: 17, color: iconColor ?? tertiaryText),
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
            prefixText: prefix != null ? '$prefix ' : null,
            prefixStyle: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: primaryText,
            ),
            suffixIcon: suffix != null
                ? Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: suffix,
                  )
                : null,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
            filled: true,
            fillColor: fieldBg,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: maxLines > 1 ? 12 : 0,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _red),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _red, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── _DropdownField ───────────────────────────────────────────────────────────
class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final String label;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8F9FF);
    final line = isDark ? const Color(0xFF253047) : _border;
    final primaryText = isDark ? const Color(0xFFF8FAFC) : _textPrimary;
    final secondaryText = isDark ? const Color(0xFFCBD5E1) : _textSecondary;
    final tertiaryText = isDark ? const Color(0xFF94A3B8) : _textTertiary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: secondaryText,
          ),
        ),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          initialValue: value,
          items: items
              .map(
                (c) => DropdownMenuItem(
                  value: c,
                  child: Text(
                    c,
                    style: TextStyle(
                      fontSize: 14,
                      color: primaryText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
          validator: (v) => v == null ? 'Required' : null,
          dropdownColor: isDark ? const Color(0xFF111827) : _cardBg,
          style: TextStyle(
            fontSize: 14,
            color: primaryText,
            fontWeight: FontWeight.w500,
          ),
          iconEnabledColor: tertiaryText,
          decoration: InputDecoration(
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Icon(
                Icons.category_outlined,
                size: 17,
                color: tertiaryText,
              ),
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
            filled: true,
            fillColor: fieldBg,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── _Banner ──────────────────────────────────────────────────────────────────
class _Banner extends StatelessWidget {
  const _Banner({
    required this.tone,
    required this.icon,
    required this.main,
    required this.sub,
    this.trailing,
  });
  final _Tone tone;
  final IconData icon;
  final String main, sub;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: _toneBg(tone),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _toneBorder(tone), width: 0.5),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: _toneFg(tone)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                main,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _toneFg(tone),
                ),
              ),
              Text(
                sub,
                style: TextStyle(
                  fontSize: 11,
                  color: _toneFg(tone).withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _toneFg(tone),
            ),
          ),
      ],
    ),
  );
}

// ─── _ImageSheet ──────────────────────────────────────────────────────────────
class _ImageSheet extends StatelessWidget {
  const _ImageSheet({
    required this.hasImage,
    required this.onGallery,
    required this.onCamera,
    required this.onRemove,
  });
  final bool hasImage;
  final VoidCallback onGallery, onCamera, onRemove;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panel = isDark ? const Color(0xFF111827) : _cardBg;
    final line = isDark ? const Color(0xFF253047) : Colors.grey[200]!;
    final primaryText = isDark ? const Color(0xFFF8FAFC) : _textPrimary;
    final secondaryText = isDark ? const Color(0xFFCBD5E1) : _textSecondary;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: panel,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 20),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Product photo',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: primaryText,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose a source',
              style: TextStyle(fontSize: 13, color: secondaryText),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _SheetOption(
                    icon: Icons.photo_library_outlined,
                    label: 'Gallery',
                    color: _primary,
                    onTap: onGallery,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SheetOption(
                    icon: Icons.camera_alt_outlined,
                    label: 'Camera',
                    color: _green,
                    onTap: onCamera,
                  ),
                ),
              ],
            ),
            if (hasImage) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: _redBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _redBorder, width: 0.5),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete_outline, color: _red, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Remove photo',
                        style: TextStyle(
                          color: _red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.12 : 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: color.withValues(alpha: isDark ? 0.28 : 0.2),
            width: 0.5,
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.2 : 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
