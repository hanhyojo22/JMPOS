import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class DatabaseHelper {
  static Database? _database;
  static const int _dbVersion = 3;

  static final DatabaseHelper instance = DatabaseHelper._init();

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('pos.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    // Products table
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode TEXT NOT NULL,
        product_name TEXT NOT NULL,
        category TEXT,
        description TEXT,
        price REAL NOT NULL,
        cost_price REAL NOT NULL,
        stock_quantity INTEGER NOT NULL,
        image_url TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Sales table
    await db.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        price REAL NOT NULL,
        total REAL NOT NULL,
        image_url TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // Users table
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        full_name TEXT,
        email TEXT,
        role TEXT DEFAULT 'staff',
        created_at TEXT
      )
    ''');

    // Insert default admin user (password: jmsolution)
    await db.insert('users', {
      'username': 'admin',
      'password_hash': _hashPassword('jmsolution'),
      'full_name': 'Juan dela Cruz',
      'email': 'admin@posapp.com',
      'role': 'admin',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE products ADD COLUMN description TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE sales ADD COLUMN image_url TEXT');
    }
  }

  Future<void> _ensureProductSchema(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(products)');
    final hasDescription = columns.cast<Map<String, Object?>>().any(
      (column) => column['name'] == 'description',
    );

    if (!hasDescription) {
      await db.execute('ALTER TABLE products ADD COLUMN description TEXT');
    }
  }

  Future<void> ensureSalesSchema() async {
    final db = await database;
    final columns = await db.rawQuery('PRAGMA table_info(sales)');
    final hasImageUrl = columns.cast<Map<String, Object?>>().any(
      (column) => column['name'] == 'image_url',
    );

    if (!hasImageUrl) {
      await db.execute('ALTER TABLE sales ADD COLUMN image_url TEXT');
    }
  }

  // ─── Password hashing ────────────────────────────────────────────────────────
  static String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // ─── Auth methods ─────────────────────────────────────────────────────────────

  /// Returns the user map if credentials are valid, null otherwise.
  Future<Map<String, dynamic>?> login(String username, String password) async {
    final db = await database;
    final hash = _hashPassword(password);

    final result = await db.query(
      'users',
      where: 'username = ? AND password_hash = ?',
      whereArgs: [username.trim().toLowerCase(), hash],
    );

    if (result.isNotEmpty) return result.first;
    return null;
  }

  /// Changes password for a given user. Returns true on success.
  Future<bool> changePassword({
    required String username,
    required String currentPassword,
    required String newPassword,
  }) async {
    final db = await database;
    final currentHash = _hashPassword(currentPassword);

    // Verify current password first
    final result = await db.query(
      'users',
      where: 'username = ? AND password_hash = ?',
      whereArgs: [username.trim().toLowerCase(), currentHash],
    );

    if (result.isEmpty) return false; // Wrong current password

    final newHash = _hashPassword(newPassword);
    await db.update(
      'users',
      {'password_hash': newHash},
      where: 'username = ?',
      whereArgs: [username.trim().toLowerCase()],
    );

    return true;
  }

  /// Returns user info (without password hash) by username.
  Future<Map<String, dynamic>?> getUserByUsername(String username) async {
    final db = await database;
    final result = await db.query(
      'users',
      columns: ['id', 'username', 'full_name', 'email', 'role', 'created_at'],
      where: 'username = ?',
      whereArgs: [username.trim().toLowerCase()],
    );
    if (result.isNotEmpty) return result.first;
    return null;
  }

  // ─── Product methods ──────────────────────────────────────────────────────────

  /// Adds a new product to the database with automatic timestamps.
  ///
  /// Returns the product id if successful, throws exception on error.
  ///
  /// Example:
  /// ```dart
  /// final productId = await DatabaseHelper.instance.addProduct(
  ///   barcode: '1234567890',
  ///   productName: 'Coca Cola 500ml',
  ///   category: 'Beverages',
  ///   price: 25.00,
  ///   costPrice: 15.00,
  ///   stockQuantity: 100,
  ///   imageUrl: 'assets/coca_cola.png',
  /// );
  /// ```
  Future<int> addProduct({
    required String barcode,
    required String productName,
    String? category,
    String? description,
    required double price,
    required double costPrice,
    required int stockQuantity,
    String? imageUrl,
  }) async {
    final db = await database;
    await _ensureProductSchema(db);
    final now = DateTime.now().toIso8601String();
    final trimmedBarcode = barcode.trim();

    if (await barcodeExists(trimmedBarcode)) {
      throw Exception('Barcode already exists');
    }

    try {
      return await db.insert('products', {
        'barcode': trimmedBarcode,
        'product_name': productName.trim(),
        'category': category?.trim(),
        'description': description?.trim(),
        'price': price,
        'cost_price': costPrice,
        'stock_quantity': stockQuantity,
        'image_url': imageUrl?.trim(),
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      throw Exception('Failed to add product: $e');
    }
  }

  Future<int> insertProduct(Map<String, dynamic> product) async {
    final db = await database;
    return await db.insert('products', product);
  }

  Future<List<Map<String, dynamic>>> getProducts() async {
    final db = await database;
    return await db.query('products');
  }

  Future<int> updateProduct(Map<String, dynamic> product) async {
    final db = await database;
    final barcode = product['barcode']?.toString().trim() ?? '';
    final id = product['id'] as int;

    if (barcode.isNotEmpty &&
        await barcodeExists(barcode, excludeProductId: id)) {
      throw Exception('Barcode already exists');
    }

    return await db.update(
      'products',
      {...product, 'barcode': barcode},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteProduct(int id) async {
    final db = await database;
    return await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Sales methods ────────────────────────────────────────────────────────────

  Future<int> insertSale(Map<String, dynamic> sale) async {
    final db = await database;
    return await db.insert('sales', sale);
  }

  Future<List<Map<String, dynamic>>> getSales() async {
    final db = await database;
    return await db.query('sales', orderBy: 'created_at DESC');
  }

  // ─── Staff management methods ──────────────────────────────────────────────────

  /// Creates a new staff user. Returns the user id if successful, -1 otherwise.
  Future<int> createStaff({
    required String username,
    required String password,
    required String fullName,
    required String email,
  }) async {
    final db = await database;
    try {
      return await db.insert('users', {
        'username': username.trim().toLowerCase(),
        'password_hash': _hashPassword(password),
        'full_name': fullName,
        'email': email.trim(),
        'role': 'staff',
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      return -1; // Username might already exist
    }
  }

  /// Gets all staff members (non-admin users).
  Future<List<Map<String, dynamic>>> getAllStaff() async {
    final db = await database;
    return await db.query(
      'users',
      where: 'role = ?',
      whereArgs: ['staff'],
      orderBy: 'created_at DESC',
    );
  }

  /// Gets all users.
  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final db = await database;
    return await db.query(
      'users',
      columns: ['id', 'username', 'full_name', 'email', 'role', 'created_at'],
      orderBy: 'created_at DESC',
    );
  }

  /// Deletes a staff member by id.
  Future<bool> deleteStaff(int userId) async {
    final db = await database;
    final result = await db.delete(
      'users',
      where: 'id = ? AND role = ?',
      whereArgs: [userId, 'staff'],
    );
    return result > 0;
  }

  /// Updates staff member info.
  Future<bool> updateStaff({
    required int userId,
    required String fullName,
    required String email,
  }) async {
    final db = await database;
    final result = await db.update(
      'users',
      {'full_name': fullName, 'email': email.trim()},
      where: 'id = ? AND role = ?',
      whereArgs: [userId, 'staff'],
    );
    return result > 0;
  }

  /// Resets a staff member's password.
  Future<bool> resetStaffPassword({
    required int userId,
    required String newPassword,
  }) async {
    final db = await database;
    final result = await db.update(
      'users',
      {'password_hash': _hashPassword(newPassword)},
      where: 'id = ?',
      whereArgs: [userId],
    );
    return result > 0;
  }

  Future<bool> barcodeExists(String barcode, {int? excludeProductId}) async {
    final db = await database;
    final trimmedBarcode = barcode.trim();
    if (trimmedBarcode.isEmpty) return false;

    final result = await db.query(
      'products',
      where: excludeProductId == null
          ? 'LOWER(barcode) = LOWER(?)'
          : 'LOWER(barcode) = LOWER(?) AND id != ?',
      whereArgs: excludeProductId == null
          ? [trimmedBarcode]
          : [trimmedBarcode, excludeProductId],
      limit: 1,
    );
    return result.isNotEmpty;
  }
}
