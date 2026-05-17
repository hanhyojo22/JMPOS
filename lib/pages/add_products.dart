import 'dart:io';
import 'package:pos_app/utils/message_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../database/database_helper.dart';

class AddProductsPage extends StatefulWidget {
  final String? initialBarcode;

  const AddProductsPage({super.key, this.initialBarcode});
  @override
  State<AddProductsPage> createState() => _AddProductsPageState();
}

class _AddProductsPageState extends State<AddProductsPage>
    with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  XFile? _pickedImage;
  OverlayEntry? _messageOverlay;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  final _nameController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _costPriceController = TextEditingController();
  final _sellingPriceController = TextEditingController();
  final _stockQuantityController = TextEditingController();

  String? _selectedCategory;

  final List<String> _categories = [
    'Beverages',
    'Groceries',
    'Snacks',
    'Household',
    'Other',
  ];

  // ── Computed ──────────────────────────────────────────────────────────────────

  double get _profitMargin {
    final cost = double.tryParse(_costPriceController.text) ?? 0;
    final sell = double.tryParse(_sellingPriceController.text) ?? 0;
    if (cost <= 0 || sell <= 0) return 0;
    return ((sell - cost) / cost) * 100;
  }

  Color get _marginColor {
    if (_profitMargin < 0) return Colors.red;
    if (_profitMargin < 20) return Colors.orange;
    return Colors.green;
  }

  double get _profit {
    final cost = double.tryParse(_costPriceController.text) ?? 0;
    final sell = double.tryParse(_sellingPriceController.text) ?? 0;
    return sell - cost;
  }

  int get _stockValue => int.tryParse(_stockQuantityController.text) ?? 0;

  Color _stockColor(int s) {
    if (s == 0) return Colors.grey;
    if (s <= 10) return Colors.orange;
    return Colors.green;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────────

  void _showBanner(String message, {bool success = false}) {
    _messageOverlay?.remove();

    _messageOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 14,
        left: 16,
        right: 16,
        child: MessageBanner(message: message, success: success),
      ),
    );

    Overlay.of(context).insert(_messageOverlay!);

    Future.delayed(const Duration(seconds: 2), () {
      _messageOverlay?.remove();
      _messageOverlay = null;
    });
  }

  @override
  void initState() {
    super.initState();

    // AUTO-FILL BARCODE FROM SCANNER
    if (widget.initialBarcode != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final barcode = widget.initialBarcode!;

        final exists = await DatabaseHelper.instance.barcodeExists(barcode);

        if (!mounted) return;

        if (exists) {
          _showBanner('Barcode already exists in database');

          // CLEAR FIELD
          _barcodeController.clear();

          return;
        }

        // ONLY SAVE IF NOT DUPLICATE
        _barcodeController.text = barcode;
      });
    }

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);

    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _nameController.dispose();
    _barcodeController.dispose();
    _descriptionController.dispose();
    _costPriceController.dispose();
    _sellingPriceController.dispose();
    _stockQuantityController.dispose();
    super.dispose();
  }

  // ── Image ─────────────────────────────────────────────────────────────────────

  Future<void> _pickImage({required ImageSource source}) async {
    final img = await _picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (img != null) setState(() => _pickedImage = img);
  }

  void _showImageSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        final bottomInset = MediaQuery.paddingOf(sheetContext).bottom;

        return SafeArea(
          top: false,
          minimum: EdgeInsets.only(bottom: bottomInset + 12),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF111827) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 20),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF334155)
                          : Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Add Product Image',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? const Color(0xFFF8FAFC) : Colors.black87,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _ImgSrcBtn(
                        icon: Icons.photo_library_outlined,
                        label: 'Gallery',
                        color: const Color(0xFF667EEA),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _pickImage(source: ImageSource.gallery);
                        },
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _ImgSrcBtn(
                        icon: Icons.camera_alt_outlined,
                        label: 'Camera',
                        color: const Color(0xFF43B89C),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _pickImage(source: ImageSource.camera);
                        },
                      ),
                    ),
                  ],
                ),
                if (_pickedImage != null) ...[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _pickedImage = null);
                      Navigator.pop(sheetContext);
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text(
                      'Remove photo',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Barcode ───────────────────────────────────────────────────────────────────

  // ── Save / Reset ──────────────────────────────────────────────────────────────

  Future<void> _saveProduct() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      // existing validation error SnackBar...
      return;
    }

    final barcode = _barcodeController.text.trim();
    if (await DatabaseHelper.instance.barcodeExists(barcode)) {
      if (!mounted) return;
      _showBanner('Barcode Already Exists ');
      return; // stop saving
    }

    setState(() => _isSaving = true);

    try {
      final newId = await DatabaseHelper.instance.addProduct(
        barcode: barcode,
        productName: _nameController.text.trim(),
        category: _selectedCategory,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        price: double.parse(_sellingPriceController.text),
        costPrice: double.parse(_costPriceController.text),
        stockQuantity: int.parse(_stockQuantityController.text),
        imageUrl: _pickedImage?.path,
      );

      // rest of your success/error handling...

      if (!mounted) return;
      setState(() => _isSaving = false);

      if (newId > 0) {
        _resetForm();
        _showBanner('Product saved successfully!', success: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showBanner('Error: $e');
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    setState(() {
      _pickedImage = null;
      _selectedCategory = null;
    });
    _nameController.clear();
    _barcodeController.clear();
    _descriptionController.clear();
    _costPriceController.clear();
    _sellingPriceController.clear();
    _stockQuantityController.clear();
  }

  // ── Hero image widget ─────────────────────────────────────────────────────────

  Widget _heroImage() {
    Widget content;
    if (_pickedImage != null) {
      content = Image.file(
        File(_pickedImage!.path),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    } else {
      content = Container(
        color: const Color(0xFFF5F6FA),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add_photo_alternate_outlined,
                size: 36,
                color: Color(0xFF667EEA),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Tap to add image',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF667EEA),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      height: 220,
      decoration: const BoxDecoration(color: Colors.white),
      child: Stack(
        children: [
          Positioned.fill(child: content),
          Positioned(
            top: 12,
            right: 12,
            child: GestureDetector(
              onTap: _showImageSheet,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.camera_alt_outlined,
                  size: 18,
                  color: Color(0xFF667EEA),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageSurface = isDark
        ? const Color(0xFF0F172A)
        : const Color(0xFFF5F6FA);
    final panelSurface = isDark ? const Color(0xFF111827) : Colors.white;
    final lineColor = isDark ? const Color(0xFF253047) : Colors.grey[100]!;
    final primaryText = isDark ? const Color(0xFFF8FAFC) : Colors.black;
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.22)
        : Colors.black.withValues(alpha: 0.05);
    final hasPrice =
        _costPriceController.text.isNotEmpty &&
        _sellingPriceController.text.isNotEmpty;
    final stockVal = _stockValue;

    return Scaffold(
      backgroundColor: pageSurface,

      appBar: AppBar(
        backgroundColor: panelSurface,
        elevation: 0,
        foregroundColor: primaryText,
        title: Text(
          'Add Product',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            onPressed: _resetForm,
            tooltip: 'Reset form',
            icon: Icon(
              Icons.refresh_rounded,
              color: isDark ? const Color(0xFFCBD5E1) : Colors.grey[600],
            ),
          ),
        ],
      ),

      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                // ── Image + Quick Stats card ──────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: panelSurface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: shadowColor,
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _showImageSheet,
                        child: _heroImage(),
                      ),
                      Divider(height: 1, color: lineColor),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: _StatTile(
                                label: 'Selling Price',
                                value: _sellingPriceController.text.isEmpty
                                    ? '—'
                                    : '₱${double.tryParse(_sellingPriceController.text)?.toStringAsFixed(2) ?? '0.00'}',
                                icon: Icons.sell_outlined,
                                color: const Color(0xFF667EEA),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _StatTile(
                                label: 'Stock',
                                value: _stockQuantityController.text.isEmpty
                                    ? '—'
                                    : '$stockVal units',
                                icon: Icons.inventory_2_outlined,
                                color: _stockQuantityController.text.isEmpty
                                    ? Colors.grey
                                    : _stockColor(stockVal),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Product Details ───────────────────────────────────
                _SectionCard(
                  title: 'Product Details',
                  icon: Icons.inventory_2_outlined,
                  children: [
                    _TF(
                      controller: _nameController,
                      label: 'Product Name',
                      hint: 'e.g. Coca Cola 500ml',
                      icon: Icons.label_outline_rounded,
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Required' : null,
                    ),

                    const SizedBox(height: 14),
                    _TF(
                      controller: _barcodeController,
                      label: 'Barcode / SKU',
                      hint: '8851234567890',
                      icon: Icons.qr_code_2_outlined,
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Required' : null,
                    ),

                    const SizedBox(height: 14),

                    DropdownButtonFormField<String>(
                      initialValue: _selectedCategory,
                      items: _categories
                          .map(
                            (c) => DropdownMenuItem(value: c, child: Text(c)),
                          )
                          .toList(),
                      decoration: InputDecoration(
                        labelText: 'Category',
                        prefixIcon: const Icon(
                          Icons.category_outlined,
                          size: 20,
                        ),
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF1E293B)
                            : Colors.grey[50],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark
                                ? const Color(0xFF334155)
                                : Colors.grey[200]!,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark
                                ? const Color(0xFF334155)
                                : Colors.grey[200]!,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF667EEA),
                            width: 2,
                          ),
                        ),
                      ),
                      onChanged: (v) => setState(() => _selectedCategory = v),
                      validator: (v) => v == null ? 'Select a category' : null,
                    ),

                    const SizedBox(height: 14),

                    _TF(
                      controller: _descriptionController,
                      label: 'Description',
                      hint: 'Optional...',
                      icon: Icons.notes_rounded,
                      maxLines: 3,
                      validator: (_) => null,
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // ── Pricing ───────────────────────────────────────────
                _SectionCard(
                  title: 'Pricing',
                  icon: Icons.payments_outlined,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _TF(
                            controller: _costPriceController,
                            label: 'Cost Price',
                            hint: '0.00',
                            icon: Icons.arrow_downward_rounded,
                            iconColor: Colors.red[400],
                            prefix: '₱',
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
                        const SizedBox(width: 12),
                        Expanded(
                          child: _TF(
                            controller: _sellingPriceController,
                            label: 'Selling Price',
                            hint: '0.00',
                            icon: Icons.arrow_upward_rounded,
                            iconColor: Colors.green[600],
                            prefix: '₱',
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

                    if (hasPrice) ...[
                      const SizedBox(height: 12),
                      _InfoBanner(
                        icon: _profitMargin >= 0
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                        color: _marginColor,
                        left: 'Margin: ${_profitMargin.toStringAsFixed(1)}%',
                        right: '₱${_profit.toStringAsFixed(2)} profit',
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 16),

                // ── Stock ─────────────────────────────────────────────
                _SectionCard(
                  title: 'Stock Management',
                  icon: Icons.warehouse_outlined,
                  children: [
                    _TF(
                      controller: _stockQuantityController,
                      label: 'Stock Quantity',
                      hint: '0',
                      icon: Icons.inventory_outlined,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        if (int.tryParse(v) == null) return 'Invalid';
                        return null;
                      },
                    ),

                    if (_stockQuantityController.text.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _InfoBanner(
                        icon: stockVal == 0
                            ? Icons.remove_shopping_cart_outlined
                            : stockVal <= 10
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline_rounded,
                        color: _stockColor(stockVal),
                        left: stockVal == 0
                            ? 'No Stock'
                            : stockVal <= 10
                            ? 'Low Stock'
                            : 'In Stock',
                        right: '$stockVal units available',
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 28),

                // ── Save button ───────────────────────────────────────
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveProduct,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF667EEA),
                      disabledBackgroundColor: const Color(
                        0xFF667EEA,
                      ).withValues(alpha: 0.6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.save_rounded, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                'Save Product',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Section card ─────────────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelSurface = isDark ? const Color(0xFF111827) : Colors.white;
    final primaryText = isDark ? const Color(0xFFF8FAFC) : Colors.black87;
    final lineColor = isDark ? const Color(0xFF253047) : Colors.grey[100]!;
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.22)
        : Colors.black.withValues(alpha: 0.05);

    return Container(
      decoration: BoxDecoration(
        color: panelSurface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: const Color(0xFF667EEA)),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: primaryText,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: lineColor),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Stat tile ────────────────────────────────────────────────────────────────
class _StatTile extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Info banner ──────────────────────────────────────────────────────────────
class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String left, right;

  const _InfoBanner({
    required this.icon,
    required this.color,
    required this.left,
    required this.right,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            left,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const Spacer(),
          Text(
            right,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Text field ───────────────────────────────────────────────────────────────
class _TF extends StatelessWidget {
  final TextEditingController controller;
  final String label, hint;
  final IconData icon;
  final Color? iconColor;
  final String? prefix;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final int maxLines;

  const _TF({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.iconColor,
    this.prefix,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
    this.validator,
    this.onChanged,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? const Color(0xFF1E293B) : Colors.grey[50]!;
    final line = isDark ? const Color(0xFF334155) : Colors.grey[200]!;
    final iconFallback = isDark ? const Color(0xFF94A3B8) : Colors.grey[500]!;

    return TextFormField(
      controller: controller,
      style: TextStyle(color: isDark ? const Color(0xFFF8FAFC) : null),
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      onChanged: onChanged,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: iconColor ?? iconFallback, size: 20),
        prefixText: prefix != null ? '$prefix ' : null,
        prefixStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Color(0xFF667EEA),
        ),
        filled: true,
        fillColor: fill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF667EEA), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
      ),
    );
  }
}

// ─── Image source button ──────────────────────────────────────────────────────
class _ImgSrcBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ImgSrcBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: color),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Barcode scanner page ─────────────────────────────────────────────────────
class BarcodeScannerPage extends StatefulWidget {
  final Function(String barcode) onDetect;

  const BarcodeScannerPage({super.key, required this.onDetect});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  bool _isScanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan Barcode'),
        elevation: 0,
      ),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (_isScanned) return;
              for (final barcode in capture.barcodes) {
                final code = barcode.rawValue;
                if (code != null) {
                  _isScanned = true;
                  widget.onDetect(code);
                  Navigator.pop(context);
                  break;
                }
              }
            },
          ),
          // Scan overlay
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF667EEA), width: 2.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                children: [
                  // Corner accents
                  for (final alignment in [
                    Alignment.topLeft,
                    Alignment.topRight,
                    Alignment.bottomLeft,
                    Alignment.bottomRight,
                  ])
                    Align(
                      alignment: alignment,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          border: Border(
                            top: alignment.y < 0
                                ? const BorderSide(
                                    color: Color(0xFF667EEA),
                                    width: 4,
                                  )
                                : BorderSide.none,
                            bottom: alignment.y > 0
                                ? const BorderSide(
                                    color: Color(0xFF667EEA),
                                    width: 4,
                                  )
                                : BorderSide.none,
                            left: alignment.x < 0
                                ? const BorderSide(
                                    color: Color(0xFF667EEA),
                                    width: 4,
                                  )
                                : BorderSide.none,
                            right: alignment.x > 0
                                ? const BorderSide(
                                    color: Color(0xFF667EEA),
                                    width: 4,
                                  )
                                : BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Align barcode within the frame',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
