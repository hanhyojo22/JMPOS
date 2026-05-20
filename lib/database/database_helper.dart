import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';
import 'package:crypto/crypto.dart';
import 'package:archive/archive_io.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class RestoreDatabaseException implements Exception {
  const RestoreDatabaseException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DatabaseHelper {
  static Database? _database;
  static const int _dbVersion = 4;
  static const String _dbPasswordKey = 'pos_sqlcipher_database_key';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static final DatabaseHelper instance = DatabaseHelper._init();

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('pos.db');
    return _database!;
  }

  Future<String> prepareDatabaseForBackup() async {
    final db = await database;
    await _migrateImageColumn(db, 'products');
    await _migrateImageColumn(db, 'sales');
    await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');

    final source = File(db.path);
    if (!await source.exists()) {
      throw Exception('Database file was not found.');
    }

    return source.path;
  }

  Future<void> _migrateImageColumn(Database db, String table) async {
    final rows = await db.query(
      table,
      columns: ['id', 'image_url'],
      where: "image_url IS NOT NULL AND TRIM(image_url) != ''",
    );

    for (final row in rows) {
      final imagePath = row['image_url']?.toString();
      final id = row['id'];
      if (imagePath == null || id == null) continue;

      final savedPath = await saveProductImage(imagePath);
      if (savedPath == null || savedPath == imagePath) continue;

      await db.update(
        table,
        {'image_url': savedPath},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<String> createBackupArchive() async {
    final dbPath = await prepareDatabaseForBackup();
    final dbDir = dirname(dbPath);
    final backupDir = Directory(join(dbDir, 'backups'));
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-');
    final archivePath = join(backupDir.path, 'pos_backup_$timestamp.posbackup');
    final portableDbPath = join(backupDir.path, 'pos_backup_$timestamp.db');

    try {
      await _createPortableDatabaseCopy(portableDbPath);
      final archive = Archive();
      final databaseBytes = await File(portableDbPath).readAsBytes();
      archive.addFile(
        ArchiveFile('pos.db', databaseBytes.length, databaseBytes),
      );

      final imageDir = Directory(await productImagesDirectoryPath());
      if (await imageDir.exists()) {
        final imageFiles = imageDir
            .listSync(recursive: true)
            .whereType<File>();
        for (final imageFile in imageFiles) {
          final relativePath = relative(
            imageFile.path,
            from: imageDir.path,
          ).replaceAll('\\', '/');
          final imageBytes = await imageFile.readAsBytes();
          archive.addFile(
            ArchiveFile(
              'product_images/$relativePath',
              imageBytes.length,
              imageBytes,
            ),
          );
        }
      }

      await File(archivePath).writeAsBytes(ZipEncoder().encode(archive));
    } finally {
      await _deleteIfExists(portableDbPath);
    }

    return archivePath;
  }

  Future<String> productImagesDirectoryPath() async {
    final db = await database;
    return join(dirname(db.path), 'product_images');
  }

  Future<String?> saveProductImage(String? imagePath) async {
    if (imagePath == null || imagePath.trim().isEmpty) return null;

    final source = File(imagePath);
    if (!await source.exists()) return imagePath;

    final imageDir = Directory(await productImagesDirectoryPath());
    if (!await imageDir.exists()) {
      await imageDir.create(recursive: true);
    }

    if (dirname(source.path) == imageDir.path) {
      return source.path;
    }

    final imageExtension = extension(source.path);
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final targetPath = join(
      imageDir.path,
      'product_$timestamp${imageExtension.isEmpty ? '.jpg' : imageExtension}',
    );

    await source.copy(targetPath);
    return targetPath;
  }

  Future<void> restoreDatabaseFromPath(String backupPath) async {
    final backup = File(backupPath);
    if (!await backup.exists()) {
      throw const RestoreDatabaseException('Backup file was not found.');
    }

    if (backupPath.toLowerCase().endsWith('.posbackup') ||
        backupPath.toLowerCase().endsWith('.zip')) {
      await _restoreBackupArchive(backup);
      return;
    }

    await _replaceDatabase((targetPath) async {
      await backup.copy(targetPath);
    });
  }

  Future<void> restoreDatabaseFromBytes(Uint8List bytes) async {
    if (bytes.isEmpty) {
      throw const RestoreDatabaseException('Backup file is empty.');
    }

    if (_looksLikeZip(bytes)) {
      await _restoreBackupArchiveBytes(bytes);
      return;
    }

    await _replaceDatabase((targetPath) async {
      await File(targetPath).writeAsBytes(bytes);
    });
  }

  Future<void> _restoreBackupArchive(File backup) async {
    await _restoreBackupArchiveBytes(await backup.readAsBytes());
  }

  Future<void> _restoreBackupArchiveBytes(Uint8List bytes) async {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final dbFile = _databaseFileFromArchive(archive);
      if (dbFile == null) {
        throw const RestoreDatabaseException(
          'This backup does not contain a database file.',
        );
      }

      await _replaceDatabase((targetPath) async {
        await File(targetPath).writeAsBytes(dbFile.content as List<int>);
      });
      await _restoreProductImagesFromArchive(archive);
    } on RestoreDatabaseException {
      rethrow;
    } on ArchiveException {
      throw const RestoreDatabaseException(
        'The selected backup file is damaged or is not a valid POS backup.',
      );
    } catch (e) {
      throw RestoreDatabaseException(_restoreFailureMessage(e));
    }
  }

  ArchiveFile? _databaseFileFromArchive(Archive archive) {
    for (final file in archive.files) {
      final normalizedName = file.name.replaceAll('\\', '/');
      if (file.isFile && basename(normalizedName) == 'pos.db') {
        return file;
      }
    }
    return null;
  }

  bool _looksLikeZip(Uint8List bytes) {
    return bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
  }

  Future<void> _replaceDatabase(
    Future<void> Function(String targetPath) writeBackup,
  ) async {
    final currentDb = await database;
    final targetPath = currentDb.path;
    final restoreBackupPath = '$targetPath.restore_backup';
    await currentDb.close();
    _database = null;

    try {
      await _deleteIfExists(restoreBackupPath);
      if (await File(targetPath).exists()) {
        await File(targetPath).rename(restoreBackupPath);
      }

      await writeBackup(targetPath);
      await _deleteIfExists('$targetPath-wal');
      await _deleteIfExists('$targetPath-shm');
      _database = await _initDB('pos.db');
      await _deleteIfExists(restoreBackupPath);
    } catch (e) {
      await _deleteIfExists(targetPath);
      if (await File(restoreBackupPath).exists()) {
        await File(restoreBackupPath).rename(targetPath);
      }
      _database = await _initDB('pos.db');
      throw RestoreDatabaseException(_restoreFailureMessage(e));
    }
  }

  String _restoreFailureMessage(Object error) {
    final details = error.toString().toLowerCase();
    if (details.contains('file is not a database') ||
        details.contains('not a database') ||
        details.contains('file is encrypted') ||
        details.contains('cipher') ||
        details.contains('malformed')) {
      return 'This backup is encrypted with a different app key or is damaged. '
          'Create a new backup from the original app, then restore that new .posbackup file.';
    }

    if (details.contains('permission') || details.contains('access is denied')) {
      return 'The app could not read or write the selected backup file. Move it to a folder you can access and try again.';
    }

    return 'Failed to restore backup. Please select a valid .posbackup or .db file.';
  }

  Future<void> _createPortableDatabaseCopy(String targetPath) async {
    final db = await database;
    await _deleteIfExists(targetPath);
    await db.execute(
      'ATTACH DATABASE ${_sqlString(targetPath)} AS backup '
      "KEY ''",
    );

    try {
      await db.rawQuery("SELECT sqlcipher_export('backup')");
      final userVersion = Sqflite.firstIntValue(
            await db.rawQuery('PRAGMA user_version'),
          ) ??
          _dbVersion;
      await db.execute('PRAGMA backup.user_version = $userVersion');
    } finally {
      await db.execute('DETACH DATABASE backup');
    }
  }

  Future<void> _restoreProductImagesFromArchive(Archive archive) async {
    final db = await database;
    final imageDir = Directory(join(dirname(db.path), 'product_images'));
    if (await imageDir.exists()) {
      await imageDir.delete(recursive: true);
    }
    await imageDir.create(recursive: true);

    for (final file in archive.files) {
      final normalizedName = file.name.replaceAll('\\', '/');
      if (!file.isFile || !normalizedName.startsWith('product_images/')) {
        continue;
      }

      final relativePath = normalizedName.substring('product_images/'.length);
      if (relativePath.isEmpty ||
          relativePath.split('/').any((segment) => segment == '..')) {
        continue;
      }

      final targetImage = File(join(imageDir.path, relativePath));
      await targetImage.parent.create(recursive: true);
      await targetImage.writeAsBytes(file.content as List<int>);
    }
  }

  Future<void> _deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    final password = await _databasePassword();
    await _encryptExistingPlaintextDatabaseIfNeeded(path, password);

    return await openDatabase(
      path,
      password: password,
      version: _dbVersion,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<String> _databasePassword() async {
    final existing = await _secureStorage.read(key: _dbPasswordKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final random = Random.secure();
    final keyBytes = List<int>.generate(32, (_) => random.nextInt(256));
    final password = base64UrlEncode(keyBytes);
    await _secureStorage.write(key: _dbPasswordKey, value: password);
    return password;
  }

  Future<void> _encryptExistingPlaintextDatabaseIfNeeded(
    String path,
    String password,
  ) async {
    final dbFile = File(path);
    if (!await dbFile.exists() || !await _isPlaintextSqliteDatabase(dbFile)) {
      return;
    }

    final encryptedPath = '$path.encrypted';
    final plaintextBackupPath = '$path.plaintext_backup';
    await _deleteIfExists(encryptedPath);
    await _deleteIfExists('$encryptedPath-wal');
    await _deleteIfExists('$encryptedPath-shm');
    await _deleteIfExists(plaintextBackupPath);

    final plainDb = await openDatabase(path);
    try {
      await plainDb.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      await plainDb.execute(
        'ATTACH DATABASE ${_sqlString(encryptedPath)} AS encrypted '
        'KEY ${_sqlString(password)}',
      );
      await plainDb.rawQuery("SELECT sqlcipher_export('encrypted')");

      final userVersion = Sqflite.firstIntValue(
            await plainDb.rawQuery('PRAGMA user_version'),
          ) ??
          _dbVersion;
      await plainDb.execute('PRAGMA encrypted.user_version = $userVersion');
      await plainDb.execute('DETACH DATABASE encrypted');
    } finally {
      await plainDb.close();
    }

    await dbFile.rename(plaintextBackupPath);
    try {
      await File(encryptedPath).rename(path);
      await _deleteIfExists('$path-wal');
      await _deleteIfExists('$path-shm');
      await _deleteIfExists('$encryptedPath-wal');
      await _deleteIfExists('$encryptedPath-shm');
      await _deleteIfExists(plaintextBackupPath);
    } catch (_) {
      if (await File(path).exists()) {
        await File(path).delete();
      }
      if (await File(plaintextBackupPath).exists()) {
        await File(plaintextBackupPath).rename(path);
      }
      rethrow;
    }
  }

  Future<bool> _isPlaintextSqliteDatabase(File file) async {
    final header = await file.openRead(0, 16).fold<List<int>>(
      <int>[],
      (bytes, chunk) => bytes..addAll(chunk),
    );
    return header.length == 16 &&
        ascii.decode(header, allowInvalid: true) == 'SQLite format 3\u0000';
  }

  String _sqlString(String value) => "'${value.replaceAll("'", "''")}'";

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
        pin_hash TEXT,
        full_name TEXT,
        email TEXT,
        role TEXT DEFAULT 'staff',
        created_at TEXT
      )
    ''');

  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE products ADD COLUMN description TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE sales ADD COLUMN image_url TEXT');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE users ADD COLUMN pin_hash TEXT');
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

  Future<Map<String, dynamic>?> loginWithPin(String pin) async {
    final db = await database;
    final hash = _hashPassword(pin);

    final result = await db.query(
      'users',
      where: 'pin_hash = ?',
      whereArgs: [hash],
      orderBy: "CASE role WHEN 'admin' THEN 0 ELSE 1 END, created_at ASC",
      limit: 1,
    );

    if (result.isNotEmpty) return result.first;
    return null;
  }

  Future<bool> ownerPinExists() async {
    final db = await database;
    final result = await db.query(
      'users',
      columns: ['id'],
      where: "role = ? AND pin_hash IS NOT NULL AND TRIM(pin_hash) != ''",
      whereArgs: ['admin'],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<bool> setOwnerPin(String pin) async {
    final db = await database;
    final result = await db.update(
      'users',
      {'pin_hash': _hashPassword(pin)},
      where: 'id = (SELECT id FROM users WHERE role = ? ORDER BY created_at ASC LIMIT 1)',
      whereArgs: ['admin'],
    );
    return result > 0;
  }

  Future<bool> hasOwnerAccount() async {
    final db = await database;
    final result = await db.query(
      'users',
      columns: ['id'],
      where: 'role = ?',
      whereArgs: ['admin'],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<int> createOwner({
    required String username,
    required String password,
    String? email,
    String? storeName,
  }) async {
    final db = await database;
    final trimmedStoreName = storeName?.trim();
    try {
      return await db.insert('users', {
        'username': username.trim().toLowerCase(),
        'password_hash': _hashPassword(password),
        'full_name': trimmedStoreName == null || trimmedStoreName.isEmpty
            ? username.trim()
            : trimmedStoreName,
        'email': email?.trim(),
        'role': 'admin',
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      return -1;
    }
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
