import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

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

  final _stockQuantityController = TextEditingController();

  String? _selectedCategory;

  final List<String> _categories = [
    'Beverages',
    'Groceries',
    'Snacks',
    'Household',
    'Other',
  ];

  // PROFIT MARGIN
  double get _profitMargin {
    final cost = double.tryParse(_costPriceController.text) ?? 0;

    final sell = double.tryParse(_sellingPriceController.text) ?? 0;

    if (cost <= 0 || sell <= 0) {
      return 0;
    }

    return ((sell - cost) / cost) * 100;
  }

  Color get _marginColor {
    if (_profitMargin < 0) {
      return Colors.red;
    }

    if (_profitMargin < 20) {
      return Colors.orange;
    }

    return Colors.green;
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

    _stockQuantityController.dispose();

    super.dispose();
  }

  // IMAGE PICKER
  Future<void> _pickImage({required ImageSource source}) async {
    final XFile? image = await _picker.pickImage(
      source: source,

      maxWidth: 800,

      maxHeight: 800,

      imageQuality: 85,
    );

    if (image != null) {
      setState(() {
        _pickedImage = image;
      });
    }
  }

  // BARCODE SCANNER
  Future<void> _scanBarcode() async {
    await Navigator.push(
      context,

      MaterialPageRoute(
        builder: (_) => BarcodeScannerPage(
          onDetect: (barcode) {
            setState(() {
              _barcodeController.text = barcode;
            });
          },
        ),
      ),
    );
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
          ],
        ),
      ),
    );
  }

  String? _validateDecimal(String? value) {
    if (value == null || value.isEmpty) {
      return 'Required';
    }

    final parsed = double.tryParse(value);

    if (parsed == null || parsed < 0) {
      return 'Enter valid number';
    }

    return null;
  }

  String? _validateInteger(String? value) {
    if (value == null || value.isEmpty) {
      return 'Required';
    }

    final parsed = int.tryParse(value);

    if (parsed == null || parsed < 0) {
      return 'Enter valid integer';
    }

    return null;
  }

  Future<void> _saveProduct() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

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

        stockQuantity: int.parse(_stockQuantityController.text),

        imageUrl: _pickedImage?.path,
      );

      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });

      if (newId > 0) {
        _resetForm();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,

            content: const Text('Product saved successfully!'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),

      appBar: AppBar(
        backgroundColor: Colors.white,

        elevation: 0,

        title: const Text('Add Product'),

        actions: [
          IconButton(
            onPressed: _resetForm,

            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),

      body: Form(
        key: _formKey,

        child: ListView(
          padding: const EdgeInsets.all(16),

          children: [
            // IMAGE
            GestureDetector(
              onTap: _showImageSourceSheet,

              child: Container(
                height: 220,

                decoration: BoxDecoration(
                  color: Colors.white,

                  borderRadius: BorderRadius.circular(20),
                ),

                child: _pickedImage == null
                    ? const Center(
                        child: Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 50,
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(20),

                        child: Image.file(
                          File(_pickedImage!.path),

                          fit: BoxFit.cover,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 24),

            // PRODUCT NAME
            _AppTextField(
              controller: _nameController,

              label: 'Product Name',

              hint: 'Coca Cola',

              icon: Icons.label_outline,

              validator: (v) {
                return v == null || v.trim().isEmpty ? 'Required' : null;
              },
            ),

            const SizedBox(height: 14),

            // BARCODE
            TextFormField(
              controller: _barcodeController,

              validator: (v) {
                return v == null || v.trim().isEmpty ? 'Required' : null;
              },

              decoration: InputDecoration(
                labelText: 'Barcode / SKU',

                hintText: '8851234567890',

                prefixIcon: const Icon(Icons.qr_code_rounded),

                suffixIcon: IconButton(
                  onPressed: _scanBarcode,

                  icon: const Icon(
                    Icons.qr_code_scanner,

                    color: Color(0xFF667EEA),
                  ),
                ),

                filled: true,

                fillColor: Colors.grey[50],

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 14),

            // CATEGORY
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,

              items: _categories.map((c) {
                return DropdownMenuItem(value: c, child: Text(c));
              }).toList(),

              decoration: InputDecoration(
                labelText: 'Category',

                filled: true,

                fillColor: Colors.grey[50],

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),

              onChanged: (v) {
                setState(() {
                  _selectedCategory = v;
                });
              },
            ),

            const SizedBox(height: 14),

            // DESCRIPTION
            _AppTextField(
              controller: _descriptionController,

              label: 'Description',

              hint: 'Optional',

              icon: Icons.notes,

              maxLines: 3,
            ),

            const SizedBox(height: 14),

            // COST PRICE
            _AppTextField(
              controller: _costPriceController,

              label: 'Cost Price',

              hint: '0.00',

              icon: Icons.arrow_downward,

              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),

              validator: _validateDecimal,

              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: 14),

            // SELLING PRICE
            _AppTextField(
              controller: _sellingPriceController,

              label: 'Selling Price',

              hint: '0.00',

              icon: Icons.arrow_upward,

              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),

              validator: _validateDecimal,

              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: 14),

            // PROFIT MARGIN
            if (_costPriceController.text.isNotEmpty &&
                _sellingPriceController.text.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),

                decoration: BoxDecoration(
                  color: _marginColor.withValues(alpha: 0.08),

                  borderRadius: BorderRadius.circular(12),
                ),

                child: Row(
                  children: [
                    Icon(Icons.trending_up, color: _marginColor),

                    const SizedBox(width: 8),

                    Text(
                      'Profit Margin: ${_profitMargin.toStringAsFixed(1)}%',

                      style: TextStyle(
                        color: _marginColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 14),

            // STOCK
            _AppTextField(
              controller: _stockQuantityController,

              label: 'Stock Quantity',

              hint: '0',

              icon: Icons.inventory_2,

              keyboardType: TextInputType.number,

              inputFormatters: [FilteringTextInputFormatter.digitsOnly],

              validator: _validateInteger,
            ),

            const SizedBox(height: 28),

            // SAVE BUTTON
            SizedBox(
              height: 56,

              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveProduct,

                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF667EEA),

                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),

                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,

                        children: [
                          Icon(Icons.save, color: Colors.white),

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
    );
  }
}

// TEXT FIELD
class _AppTextField extends StatelessWidget {
  final TextEditingController controller;

  final String label;

  final String hint;

  final IconData icon;

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

    this.keyboardType = TextInputType.text,

    this.inputFormatters,

    this.validator,

    this.onChanged,

    this.maxLines = 1,

    super.key,
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

        prefixIcon: Icon(icon),

        filled: true,

        fillColor: Colors.grey[50],

        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

// IMAGE SOURCE BUTTON
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

    super.key,
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
        ),

        child: Column(
          children: [
            Icon(icon, size: 32, color: color),

            const SizedBox(height: 8),

            Text(
              label,

              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

// BARCODE SCANNER PAGE
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
      ),

      body: MobileScanner(
        onDetect: (capture) {
          if (_isScanned) return;

          final List<Barcode> barcodes = capture.barcodes;

          for (final barcode in barcodes) {
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
    );
  }
}
