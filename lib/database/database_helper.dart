import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class DatabaseHelper {
  static Database? _database;

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
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    // Products table
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode TEXT,
        product_name TEXT,
        price REAL,
        stock_quantity INTEGER
      )
    ''');

    // Sales table
    await db.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        total_amount REAL,
        created_at TEXT
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

    // Insert default admin user (password: jmsolution123)
    await db.insert('users', {
      'username': 'admin',
      'password_hash': _hashPassword('jmsolution123'),
      'full_name': 'Juan dela Cruz',
      'email': 'admin@posapp.com',
      'role': 'admin',
      'created_at': DateTime.now().toIso8601String(),
    });
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
    return await db.update(
      'products',
      product,
      where: 'id = ?',
      whereArgs: [product['id']],
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
}
