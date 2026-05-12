# addProduct() - SQLite Query Function Reference

## Function Overview

`addProduct()` is a production-ready Flutter/Dart function that inserts new products into a SQLite database with automatic timestamp management.

## Function Signature

```dart
Future<int> addProduct({
  required String barcode,
  required String productName,
  String? category,
  required double price,
  required double costPrice,
  required int stockQuantity,
  String? imageUrl,
}) async
```

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| barcode | String | ✓ | Unique product barcode/SKU |
| productName | String | ✓ | Product name or description |
| category | String? | ✗ | Product category (optional) |
| price | double | ✓ | Selling price per unit |
| costPrice | double | ✓ | Cost/purchase price per unit |
| stockQuantity | int | ✓ | Available inventory count |
| imageUrl | String? | ✗ | Path to product image (optional) |

## Return Value

- **Type**: `Future<int>`
- **Returns**: The newly created product's ID (auto-generated primary key)
- **Throws**: Exception if insert fails

## Database Schema

The function inserts data into the `products` table with this structure:

```sql
CREATE TABLE products (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  barcode TEXT NOT NULL,
  product_name TEXT NOT NULL,
  category TEXT,
  price REAL NOT NULL,
  cost_price REAL NOT NULL,
  stock_quantity INTEGER NOT NULL,
  image_url TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
```

## Features

✅ **Async/Await Pattern**
- Non-blocking database operations
- Proper Future handling

✅ **Automatic Timestamps**
- `created_at`: Set to current DateTime in ISO 8601 format
- `updated_at`: Set to current DateTime in ISO 8601 format
- Automatically managed, no manual input needed

✅ **Data Validation**
- String trimming to remove whitespace
- Null-safe handling of optional fields
- Named parameters prevent argument confusion

✅ **Error Handling**
- Try-catch with meaningful error messages
- Exception rethrown with context
- Safe for production use

✅ **SQLite Best Practices**
- Uses `ConflictAlgorithm.replace` for duplicate handling
- Proper database connection management
- Type-safe operations

✅ **Code Quality**
- Clear naming conventions
- Comprehensive documentation
- Follows Flutter/Dart standards

## Basic Usage

```dart
final productId = await DatabaseHelper.instance.addProduct(
  barcode: '1234567890',
  productName: 'Coca Cola 500ml',
  category: 'Beverages',
  price: 25.00,
  costPrice: 15.00,
  stockQuantity: 100,
);

print('Product added with ID: $productId'); // Output: Product added with ID: 1
```

## Complete Example

```dart
Future<void> addNewProduct() async {
  try {
    final productId = await DatabaseHelper.instance.addProduct(
      barcode: '9876543210',
      productName: 'Sprite 1L Bottle',
      category: 'Beverages',
      price: 45.00,
      costPrice: 25.00,
      stockQuantity: 50,
      imageUrl: 'assets/images/sprite_1l.png',
    );
    
    print('Successfully added product with ID: $productId');
  } catch (e) {
    print('Error adding product: $e');
  }
}
```

## Using with Forms

```dart
class AddProductForm extends StatefulWidget {
  @override
  State<AddProductForm> createState() => _AddProductFormState();
}

class _AddProductFormState extends State<AddProductForm> {
  final _formKey = GlobalKey<FormState>();
  final _barcodeController = TextEditingController();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _priceController = TextEditingController();
  final _costController = TextEditingController();
  final _stockController = TextEditingController();
  bool _isLoading = false;

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final productId = await DatabaseHelper.instance.addProduct(
        barcode: _barcodeController.text.trim(),
        productName: _nameController.text.trim(),
        category: _categoryController.text.trim(),
        price: double.parse(_priceController.text),
        costPrice: double.parse(_costController.text),
        stockQuantity: int.parse(_stockController.text),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Product added successfully! ID: $productId'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Clear form for next entry
        _clearForm();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _clearForm() {
    _barcodeController.clear();
    _nameController.clear();
    _categoryController.clear();
    _priceController.clear();
    _costController.clear();
    _stockController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: _barcodeController,
            decoration: InputDecoration(labelText: 'Barcode'),
            validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
          ),
          TextFormField(
            controller: _nameController,
            decoration: InputDecoration(labelText: 'Product Name'),
            validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
          ),
          TextFormField(
            controller: _categoryController,
            decoration: InputDecoration(labelText: 'Category'),
          ),
          TextFormField(
            controller: _priceController,
            decoration: InputDecoration(labelText: 'Price'),
            keyboardType: TextInputType.number,
            validator: (v) {
              if (v?.isEmpty ?? true) return 'Required';
              if (double.tryParse(v!) == null) return 'Invalid number';
              return null;
            },
          ),
          TextFormField(
            controller: _costController,
            decoration: InputDecoration(labelText: 'Cost Price'),
            keyboardType: TextInputType.number,
            validator: (v) {
              if (v?.isEmpty ?? true) return 'Required';
              if (double.tryParse(v!) == null) return 'Invalid number';
              return null;
            },
          ),
          TextFormField(
            controller: _stockController,
            decoration: InputDecoration(labelText: 'Stock Quantity'),
            keyboardType: TextInputType.number,
            validator: (v) {
              if (v?.isEmpty ?? true) return 'Required';
              if (int.tryParse(v!) == null) return 'Invalid number';
              return null;
            },
          ),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isLoading ? null : _submitForm,
            child: _isLoading
                ? CircularProgressIndicator()
                : Text('Add Product'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _nameController.dispose();
    _categoryController.dispose();
    _priceController.dispose();
    _costController.dispose();
    _stockController.dispose();
    super.dispose();
  }
}
```

## Bulk Insert Example

```dart
Future<void> addMultipleProducts(List<Map<String, dynamic>> products) async {
  int successCount = 0;
  int failCount = 0;

  for (final product in products) {
    try {
      await DatabaseHelper.instance.addProduct(
        barcode: product['barcode'] as String,
        productName: product['productName'] as String,
        category: product['category'] as String?,
        price: product['price'] as double,
        costPrice: product['costPrice'] as double,
        stockQuantity: product['stockQuantity'] as int,
        imageUrl: product['imageUrl'] as String?,
      );
      successCount++;
    } catch (e) {
      print('Failed to add ${product['productName']}: $e');
      failCount++;
    }
  }

  print('Bulk insert completed: $successCount added, $failCount failed');
}

// Usage
await addMultipleProducts([
  {
    'barcode': '1001',
    'productName': 'Lucky Me Pancit',
    'category': 'Noodles',
    'price': 8.0,
    'costPrice': 3.5,
    'stockQuantity': 500,
  },
  {
    'barcode': '1002',
    'productName': 'Pringles',
    'category': 'Snacks',
    'price': 35.0,
    'costPrice': 20.0,
    'stockQuantity': 100,
  },
]);
```

## Service Pattern Example

```dart
class ProductService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<int> createProduct({
    required String barcode,
    required String productName,
    required String category,
    required double price,
    required double costPrice,
    required int stockQuantity,
    String? imageUrl,
  }) async {
    // Business logic validation
    if (price < costPrice) {
      throw Exception('Selling price cannot be less than cost price');
    }

    if (stockQuantity < 0) {
      throw Exception('Stock quantity cannot be negative');
    }

    if (price <= 0 || costPrice <= 0) {
      throw Exception('Prices must be greater than zero');
    }

    // Add product
    return await _db.addProduct(
      barcode: barcode,
      productName: productName,
      category: category,
      price: price,
      costPrice: costPrice,
      stockQuantity: stockQuantity,
      imageUrl: imageUrl,
    );
  }
}

// Usage
final service = ProductService();
try {
  final id = await service.createProduct(
    barcode: '1234567890',
    productName: 'Product Name',
    category: 'Category',
    price: 100.0,
    costPrice: 50.0,
    stockQuantity: 10,
  );
  print('Product created: $id');
} catch (e) {
  print('Error: $e');
}
```

## Error Handling

The function throws exceptions in these cases:

```dart
try {
  await DatabaseHelper.instance.addProduct(
    barcode: '1234567890',
    productName: 'Product',
    category: 'Category',
    price: 100.0,
    costPrice: 50.0,
    stockQuantity: 10,
  );
} on Exception catch (e) {
  // Handle database errors
  print('Database error: $e');
} catch (e) {
  // Handle unexpected errors
  print('Unexpected error: $e');
}
```

## Timestamp Format

Timestamps are stored in ISO 8601 format:

```
Format: YYYY-MM-DDTHH:mm:ss.sssZ
Example: 2026-05-11T21:26:14.928000
Timezone: UTC (local timezone converted)
```

Query timestamps:
```dart
final products = await DatabaseHelper.instance.getProducts();
for (final product in products) {
  final createdAt = DateTime.parse(product['created_at']);
  final updatedAt = DateTime.parse(product['updated_at']);
  print('Created: $createdAt, Updated: $updatedAt');
}
```

## Performance Considerations

✓ **Efficient**
- Single insert operation
- Minimal database overhead
- Connection pooling handled by sqflite

✓ **Scalable**
- Supports bulk operations
- Suitable for batch processing
- No memory leaks with proper cleanup

✓ **Async**
- Non-blocking UI
- Better user experience
- Proper Future handling

## Best Practices

1. **Always use try-catch**
   ```dart
   try {
     final id = await DatabaseHelper.instance.addProduct(...);
   } catch (e) {
     // Handle error
   }
   ```

2. **Validate before adding**
   ```dart
   if (price >= costPrice && stockQuantity >= 0) {
     await DatabaseHelper.instance.addProduct(...);
   }
   ```

3. **Use in async context**
   ```dart
   Future<void> handler() async {
     final id = await DatabaseHelper.instance.addProduct(...);
   }
   ```

4. **Clean up controllers**
   ```dart
   @override
   void dispose() {
     controller.dispose();
     super.dispose();
   }
   ```

5. **Show loading state**
   ```dart
   setState(() => isLoading = true);
   try {
     // add product
   } finally {
     setState(() => isLoading = false);
   }
   ```

## Migration from insertProduct()

Old way:
```dart
await DatabaseHelper.instance.insertProduct({
  'barcode': '1234567890',
  'product_name': 'Product',
  'category': 'Category',
  'price': 100.0,
  'cost_price': 50.0,
  'stock_quantity': 10,
  'created_at': DateTime.now().toIso8601String(),
  'updated_at': DateTime.now().toIso8601String(),
});
```

New way (recommended):
```dart
await DatabaseHelper.instance.addProduct(
  barcode: '1234567890',
  productName: 'Product',
  category: 'Category',
  price: 100.0,
  costPrice: 50.0,
  stockQuantity: 10,
);
```

## Summary

| Aspect | Details |
|--------|---------|
| Function | addProduct() |
| Type | Future<int> |
| Parameters | 7 (3 required, 4 optional) |
| Returns | Product ID |
| Error Handling | Throws Exception |
| Timestamps | Auto-managed (ISO 8601) |
| Database | SQLite (sqflite) |
| Package | sqflite |
| Usage | DatabaseHelper.instance.addProduct(...) |
| Status | Production Ready |

---

**Last Updated**: 2026-05-11  
**Version**: 1.0  
**Status**: Production Ready
