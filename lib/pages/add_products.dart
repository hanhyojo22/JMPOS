import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../database/database_helper.dart';

class AddProductsPage extends StatefulWidget {
  const AddProductsPage({super.key});

  @override
  State<AddProductsPage> createState() => _AddProductsPageState();
}

class _AddProductsPageState extends State<AddProductsPage>
    with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  XFile? _pickedImage;
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
  final _initialStockController = TextEditingController();
  final _quantityAddedController = TextEditingController();

  String? _selectedCategory;
  final List<String> _categories = [
    'Beverages',
    'Groceries',
    'Snacks',
    'Household',
    'Other',
  ];

  // Computed profit margin
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

  int get _totalStock {
    final initial = int.tryParse(_initialStockController.text) ?? 0;
    final added = int.tryParse(_quantityAddedController.text) ?? 0;
    return initial + added;
  }

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
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
    _initialStockController.dispose();
    _quantityAddedController.dispose();
    super.dispose();
  }

  Future<void> _pickImage({required ImageSource source}) async {
    final XFile? image = await _picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (image != null) setState(() => _pickedImage = image);
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 20),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Select Image Source',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _ImageSourceBtn(
                    icon: Icons.photo_library_outlined,
                    label: 'Gallery',
                    color: const Color(0xFF667EEA),
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(source: ImageSource.gallery);
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _ImageSourceBtn(
                    icon: Icons.camera_alt_outlined,
                    label: 'Camera',
                    color: const Color(0xFF43B89C),
                    onTap: () {
                      Navigator.pop(context);
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
                  Navigator.pop(context);
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
  }

  String? _validateDecimal(String? value) {
    if (value == null || value.isEmpty) return 'Required';
    final parsed = double.tryParse(value);
    if (parsed == null || parsed < 0) return 'Enter a valid number';
    return null;
  }

  String? _validateInteger(String? value) {
    if (value == null || value.isEmpty) return 'Required';
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 0) return 'Enter a valid integer';
    return null;
  }

  Future<void> _saveProduct() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      // Scroll to first error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 8),
              Text('Please fix the errors above'),
            ],
          ),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final newId = await DatabaseHelper.instance.addProduct(
        barcode: _barcodeController.text.trim(),
        productName: _nameController.text.trim(),
        category: _selectedCategory,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        price: double.parse(_sellingPriceController.text),
        costPrice: double.parse(_costPriceController.text),
        stockQuantity: _totalStock,
        imageUrl: _pickedImage?.path,
      );

      if (!mounted) return;
      setState(() => _isSaving = false);

      if (newId > 0) {
        _resetForm();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Product saved successfully!'),
              ],
            ),
            backgroundColor: Colors.green[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to save product'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red[700]),
      );
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
    _initialStockController.clear();
    _quantityAddedController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            expandedHeight: 60,
            pinned: true,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 0,
            title: const Text(
              'Add Product',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            actions: [
              TextButton(
                onPressed: _resetForm,
                child: Text('Reset', style: TextStyle(color: Colors.grey[500])),
              ),
            ],
          ),
        ],
        body: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                children: [
                  // ── Image Picker ──────────────────────────────────
                  _SectionLabel(label: 'Product Image'),
                  GestureDetector(
                    onTap: _showImageSourceSheet,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 220,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _pickedImage != null
                              ? const Color(0xFF667EEA).withValues(alpha: 0.4)
                              : Colors.grey.shade200,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: _pickedImage == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF667EEA,
                                    ).withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.add_photo_alternate_outlined,
                                    size: 36,
                                    color: Color(0xFF667EEA),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Tap to add product image',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF667EEA),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Gallery or Camera',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[400],
                                  ),
                                ),
                              ],
                            )
                          : Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: Image.file(
                                    File(_pickedImage!.path),
                                    width: double.infinity,
                                    height: 220,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: 10,
                                  right: 10,
                                  child: GestureDetector(
                                    onTap: _showImageSourceSheet,
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.55,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.edit,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Product Details ───────────────────────────────
                  _SectionCard(
                    title: 'Product Details',
                    icon: Icons.inventory_2_outlined,
                    children: [
                      _AppTextField(
                        controller: _nameController,
                        label: 'Product Name',
                        hint: 'e.g. Coca Cola 500ml',
                        icon: Icons.label_outline_rounded,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Product name is required'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      _AppTextField(
                        controller: _barcodeController,
                        label: 'Barcode / SKU',
                        hint: 'e.g. 8851234567890',
                        icon: Icons.qr_code_rounded,
                        keyboardType: TextInputType.text,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Barcode is required'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      // Category dropdown
                      DropdownButtonFormField<String>(
                        initialValue: _selectedCategory,

                        items: _categories
                            .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)),
                            )
                            .toList(),

                        decoration: InputDecoration(
                          labelText: 'Category',

                          prefixIcon: const Icon(Icons.category_outlined),

                          filled: true,

                          fillColor: Colors.grey[50],

                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),

                            borderSide: BorderSide(color: Colors.grey[200]!),
                          ),

                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),

                            borderSide: BorderSide(color: Colors.grey[200]!),
                          ),

                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),

                            borderSide: const BorderSide(
                              color: Color(0xFF667EEA),
                              width: 2,
                            ),
                          ),
                        ),

                        onChanged: (v) {
                          setState(() {
                            _selectedCategory = v;
                          });
                        },

                        validator: (v) {
                          return v == null ? 'Select a category' : null;
                        },
                      ),
                      const SizedBox(height: 14),
                      _AppTextField(
                        controller: _descriptionController,
                        label: 'Description',
                        hint: 'Optional product description...',
                        icon: Icons.notes_rounded,
                        maxLines: 3,
                        validator: (_) => null, // optional
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Pricing ───────────────────────────────────────
                  _SectionCard(
                    title: 'Pricing',
                    icon: Icons.payments_outlined,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _AppTextField(
                              controller: _costPriceController,
                              label: 'Cost Price',
                              hint: '0.00',
                              icon: Icons.arrow_downward_rounded,
                              iconColor: Colors.red[400],
                              prefix: '₱',
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d{0,2}'),
                                ),
                              ],
                              validator: _validateDecimal,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _AppTextField(
                              controller: _sellingPriceController,
                              label: 'Selling Price',
                              hint: '0.00',
                              icon: Icons.arrow_upward_rounded,
                              iconColor: Colors.green[600],
                              prefix: '₱',
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d{0,2}'),
                                ),
                              ],
                              validator: _validateDecimal,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),

                      // Live profit margin
                      if (_costPriceController.text.isNotEmpty &&
                          _sellingPriceController.text.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _marginColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _marginColor.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _profitMargin >= 0
                                    ? Icons.trending_up_rounded
                                    : Icons.trending_down_rounded,
                                color: _marginColor,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Profit Margin: ',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              ),
                              Text(
                                '${_profitMargin.toStringAsFixed(1)}%',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: _marginColor,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '₱${((double.tryParse(_sellingPriceController.text) ?? 0) - (double.tryParse(_costPriceController.text) ?? 0)).toStringAsFixed(2)} profit',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _marginColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Inventory ─────────────────────────────────────
                  _SectionCard(
                    title: 'Inventory',
                    icon: Icons.warehouse_outlined,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _AppTextField(
                              controller: _initialStockController,
                              label: 'Initial Stock',
                              hint: '0',
                              icon: Icons.inventory_outlined,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              validator: _validateInteger,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _AppTextField(
                              controller: _quantityAddedController,
                              label: 'Qty Added',
                              hint: '0',
                              icon: Icons.add_box_outlined,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              validator: _validateInteger,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),

                      // Total stock preview
                      if (_initialStockController.text.isNotEmpty ||
                          _quantityAddedController.text.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF667EEA,
                            ).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(
                                0xFF667EEA,
                              ).withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.summarize_outlined,
                                color: Color(0xFF667EEA),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Total Stock on Save: ',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              ),
                              Text(
                                '$_totalStock units',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF667EEA),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 28),

                  // ── Save Button ───────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveProduct,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF667EEA),
                        disabledBackgroundColor: Colors.grey[300],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 3,
                        shadowColor: const Color(
                          0xFF667EEA,
                        ).withValues(alpha: 0.4),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.save_rounded, color: Colors.white),
                                SizedBox(width: 10),
                                Text(
                                  'Save Product',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
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
      ),
    );
  }
}

// ─── Section Label ────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.grey[500],
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// ─── Section Card ─────────────────────────────────────────────────────────────
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey[100]),
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

// ─── App Text Field ───────────────────────────────────────────────────────────
class _AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final Color? iconColor;
  final String? prefix;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final int maxLines;

  const _AppTextField({
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
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      onChanged: onChanged,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: iconColor ?? Colors.grey[500], size: 20),
        prefixText: prefix != null ? '$prefix ' : null,
        prefixStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Color(0xFF667EEA),
        ),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[200]!),
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

// ─── Image Source Button ──────────────────────────────────────────────────────
class _ImageSourceBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ImageSourceBtn({
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
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
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
