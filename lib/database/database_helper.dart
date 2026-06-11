import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';
import 'package:crypto/crypto.dart';
import 'package:archive/archive_io.dart';
import 'package:pos_app/models/receipt_discount_preset.dart';
import 'package:pos_app/services/supabase_sync_service.dart';
import 'package:pos_app/utils/login_input_validator.dart';

class RestoreDatabaseException implements Exception {
  const RestoreDatabaseException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ProductImageConnectionReport {
  const ProductImageConnectionReport({
    required this.availableImages,
    required this.connected,
    required this.normalized,
  });

  final int availableImages;
  final int connected;
  final int normalized;
}

class DatabaseHelper {
  static Database? _database;
  static bool _syncInProgress = false;
  static bool _cloudRestoreInProgress = false;
  static const int _dbVersion = 14;
  static const saleCompletionGracePeriod = Duration(seconds: 10);
  static const String _dbPasswordKey = 'pos_sqlcipher_database_key';
  static const int _productImageSize = 300;
  static const int _productImageJpegQuality = 82;
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

    final timestamp = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
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
        final imageFiles = imageDir.listSync(recursive: true).whereType<File>();
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

    final source = File(imagePath.trim());
    if (!await source.exists()) return imagePath;

    final imageDir = Directory(await productImagesDirectoryPath());
    if (!await imageDir.exists()) {
      await imageDir.create(recursive: true);
    }

    final sourcePath = normalize(source.absolute.path);
    final imageDirPath = normalize(imageDir.absolute.path);
    final isStoredProductImage = normalize(dirname(sourcePath)) == imageDirPath;
    if (isStoredProductImage && extension(sourcePath).toLowerCase() == '.jpg') {
      return source.path;
    }

    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final targetPath = join(imageDir.path, 'product_$timestamp.jpg');

    try {
      final decoded = img.decodeImage(await source.readAsBytes());
      if (decoded == null) {
        throw Exception('Unsupported image format.');
      }

      final oriented = img.bakeOrientation(decoded);
      final resized = img.copyResizeCropSquare(
        oriented,
        size: _productImageSize,
      );
      final optimizedBytes = img.encodeJpg(
        resized,
        quality: _productImageJpegQuality,
      );

      await File(targetPath).writeAsBytes(optimizedBytes, flush: true);
      return targetPath;
    } catch (e) {
      await _deleteIfExists(targetPath);
      throw Exception('Failed to optimize product image: $e');
    }
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

  Future<void> restoreDatabaseFromPathWithAudit({
    required String backupPath,
    required String user,
  }) async {
    await restoreDatabaseFromPath(backupPath);
    await recordAuditLog(
      user: user,
      action: 'backup_restore',
      details: _auditDetails({'source': basename(backupPath)}),
    );
  }

  Future<void> restoreDatabaseFromBytesWithAudit({
    required Uint8List bytes,
    required String user,
    String? fileName,
  }) async {
    await restoreDatabaseFromBytes(bytes);
    await recordAuditLog(
      user: user,
      action: 'backup_restore',
      details: _auditDetails({'source': fileName, 'bytes': bytes.length}),
    );
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

    if (details.contains('permission') ||
        details.contains('access is denied')) {
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
      final userVersion =
          Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')) ??
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
      onOpen: (db) async {
        await _ensureSalesSchema(db);
        await _createShiftsTable(db);
        await _createShiftReadingsTable(db);
        await _createSyncQueueTable(db);
        await _ensureCloudIdentitySchema(db);
        await _createIndexes(db);
      },
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

      final userVersion =
          Sqflite.firstIntValue(
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
    final header = await file
        .openRead(0, 16)
        .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
    return header.length == 16 &&
        ascii.decode(header, allowInvalid: true) == 'SQLite format 3\u0000';
  }

  String _sqlString(String value) => "'${value.replaceAll("'", "''")}'";

  Future _createDB(Database db, int version) async {
    // Products table
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cloud_id TEXT,
        barcode TEXT NOT NULL,
        product_name TEXT NOT NULL,
        category TEXT,
        description TEXT,
        price REAL NOT NULL,
        discount_percent REAL,
        discount_enabled INTEGER NOT NULL DEFAULT 0,
        cost_price REAL NOT NULL,
        stock_quantity INTEGER NOT NULL,
        image_url TEXT,
        pending_delete INTEGER NOT NULL DEFAULT 0,
        pending_delete_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Sales table
    await db.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cloud_id TEXT,
        product_id INTEGER NOT NULL,
        product_cloud_id TEXT,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        price REAL NOT NULL,
        original_price REAL,
        product_discount_percent REAL,
        product_discount_amount REAL,
        cost_price REAL,
        total REAL NOT NULL,
        image_url TEXT,
        voided_at TEXT,
        voided_by TEXT,
        void_reason TEXT,
        completion_due_at TEXT,
        completed_at TEXT,
        receipt_number TEXT,
        receipt_subtotal REAL,
        receipt_discount_amount REAL,
        receipt_discount_type TEXT,
        receipt_discount_value REAL,
        shift_id INTEGER,
        shift_cloud_id TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // Users table
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cloud_id TEXT,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        pin_hash TEXT,
        full_name TEXT,
        email TEXT,
        role TEXT DEFAULT 'staff',
        created_at TEXT
      )
    ''');

    await _createAuditLogTable(db);
    await _createSyncQueueTable(db);
    await _createReceiptDiscountsTable(db);
    await _createShiftsTable(db);
    await _createShiftReadingsTable(db);
    await _seedDefaultReceiptDiscounts(db);

    await _createIndexes(db);
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
    if (oldVersion < 6) {
      await _createAuditLogTable(db);
    }
    if (oldVersion < 7) {
      await _ensureSalesSchema(db);
    }
    if (oldVersion < 7) {
      await _createIndexes(db);
    }
    if (oldVersion < 8) {
      await _createSyncQueueTable(db);
      await _createIndexes(db);
    }
    if (oldVersion < 9) {
      await _ensureProductSchema(db);
    }
    if (oldVersion < 10) {
      await _ensureSalesSchema(db);
    }
    if (oldVersion < 11) {
      await _createReceiptDiscountsTable(db);
      await _seedDefaultReceiptDiscounts(db);
    }
    if (oldVersion < 12) {
      await _ensureSalesSchema(db);
      await _createShiftsTable(db);
      await _createShiftReadingsTable(db);
      await _createIndexes(db);
    }
    if (oldVersion < 13) {
      await _ensureProductSchema(db);
      await _ensureSalesSchema(db);
    }
    if (oldVersion < 14) {
      await _ensureCloudIdentitySchema(db);
    }
  }

  Future<void> _createAuditLogTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS audit_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cloud_id TEXT,
        user TEXT NOT NULL,
        action TEXT NOT NULL,
        details TEXT,
        timestamp TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createSyncQueueTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        queue_key TEXT NOT NULL UNIQUE,
        table_name TEXT NOT NULL,
        local_id TEXT NOT NULL,
        cloud_id TEXT,
        operation TEXT NOT NULL,
        payload TEXT NOT NULL,
        base_revision INTEGER NOT NULL DEFAULT 0,
        cloud_revision INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending',
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        conflict_details TEXT,
        next_retry_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        synced_at TEXT
      )
    ''');
    await _ensureSyncQueueSchema(db);
  }

  Future<void> _createReceiptDiscountsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS receipt_discounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        percent REAL NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createShiftsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS shifts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cloud_id TEXT,
        status TEXT NOT NULL DEFAULT 'open',
        opened_by TEXT NOT NULL,
        opened_at TEXT NOT NULL,
        opening_cash REAL NOT NULL DEFAULT 0,
        closed_by TEXT,
        closed_at TEXT,
        closing_cash REAL,
        expected_cash REAL,
        over_short REAL,
        z_reading_number TEXT
      )
    ''');
  }

  Future<void> _createShiftReadingsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS shift_readings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cloud_id TEXT,
        shift_id INTEGER NOT NULL,
        shift_cloud_id TEXT,
        type TEXT NOT NULL,
        created_by TEXT NOT NULL,
        created_at TEXT NOT NULL,
        opening_cash REAL NOT NULL DEFAULT 0,
        sales_total REAL NOT NULL DEFAULT 0,
        void_total REAL NOT NULL DEFAULT 0,
        receipt_count INTEGER NOT NULL DEFAULT 0,
        item_count INTEGER NOT NULL DEFAULT 0,
        expected_cash REAL NOT NULL DEFAULT 0,
        counted_cash REAL,
        over_short REAL
      )
    ''');
  }

  Future<void> _seedDefaultReceiptDiscounts(DatabaseExecutor db) async {
    final count =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM receipt_discounts'),
        ) ??
        0;
    if (count > 0) return;

    final now = DateTime.now().toIso8601String();
    final defaults = [
      const ReceiptDiscountPreset(
        name: 'Senior Citizen',
        percent: 20,
        sortOrder: 10,
      ),
      const ReceiptDiscountPreset(name: 'PWD', percent: 20, sortOrder: 20),
      const ReceiptDiscountPreset(name: 'Employee', percent: 10, sortOrder: 30),
      const ReceiptDiscountPreset(name: 'Promo', percent: 5, sortOrder: 40),
    ];

    for (final discount in defaults) {
      await db.insert('receipt_discounts', {
        ...discount.toMap(),
        'created_at': now,
        'updated_at': now,
      });
    }
  }

  Future<void> _ensureSyncQueueSchema(DatabaseExecutor db) async {
    final columns = await db.rawQuery('PRAGMA table_info(sync_queue)');
    final columnNames = columns
        .cast<Map<String, Object?>>()
        .map((column) => column['name'])
        .toSet();

    if (!columnNames.contains('next_retry_at')) {
      await db.execute('ALTER TABLE sync_queue ADD COLUMN next_retry_at TEXT');
    }
    if (!columnNames.contains('base_revision')) {
      await db.execute(
        'ALTER TABLE sync_queue ADD COLUMN base_revision INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!columnNames.contains('cloud_revision')) {
      await db.execute(
        'ALTER TABLE sync_queue ADD COLUMN cloud_revision INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!columnNames.contains('conflict_details')) {
      await db.execute(
        'ALTER TABLE sync_queue ADD COLUMN conflict_details TEXT',
      );
    }
    if (!columnNames.contains('cloud_id')) {
      await db.execute('ALTER TABLE sync_queue ADD COLUMN cloud_id TEXT');
    }
  }

  Future<void> _ensureCloudIdentitySchema(Database db) async {
    await _ensureProductSchema(db);
    await _ensureSalesSchema(db);
    await _createShiftsTable(db);
    await _createShiftReadingsTable(db);
    await _createAuditLogTable(db);
    await _createSyncQueueTable(db);

    await _ensureTableColumn(db, 'products', 'cloud_id', 'TEXT');
    await _ensureTableColumn(db, 'sales', 'cloud_id', 'TEXT');
    await _ensureTableColumn(db, 'sales', 'product_cloud_id', 'TEXT');
    await _ensureTableColumn(db, 'sales', 'shift_cloud_id', 'TEXT');
    await _ensureTableColumn(db, 'users', 'cloud_id', 'TEXT');
    await _ensureTableColumn(db, 'audit_logs', 'cloud_id', 'TEXT');
    await _ensureTableColumn(db, 'shifts', 'cloud_id', 'TEXT');
    await _ensureTableColumn(db, 'shift_readings', 'cloud_id', 'TEXT');
    await _ensureTableColumn(db, 'shift_readings', 'shift_cloud_id', 'TEXT');

    await _backfillCloudIds(db, 'products');
    await _backfillCloudIds(db, 'sales');
    await _backfillCloudIds(db, 'users');
    await _backfillCloudIds(db, 'audit_logs');
    await _backfillCloudIds(db, 'shifts');
    await _backfillCloudIds(db, 'shift_readings');
    await _backfillSalesCloudRelationships(db);
    await _backfillShiftReadingCloudRelationships(db);
  }

  Future<void> _ensureTableColumn(
    DatabaseExecutor db,
    String tableName,
    String columnName,
    String columnType,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($tableName)');
    final hasColumn = columns.cast<Map<String, Object?>>().any(
      (column) => column['name'] == columnName,
    );
    if (!hasColumn) {
      await db.execute(
        'ALTER TABLE $tableName ADD COLUMN $columnName $columnType',
      );
    }
  }

  Future<void> _backfillCloudIds(DatabaseExecutor db, String tableName) async {
    final rows = await db.query(
      tableName,
      columns: ['id'],
      where: "cloud_id IS NULL OR TRIM(cloud_id) = ''",
    );
    for (final row in rows) {
      await db.update(
        tableName,
        {'cloud_id': _newCloudId()},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  Future<void> _backfillSalesCloudRelationships(DatabaseExecutor db) async {
    final rows = await db.query(
      'sales',
      columns: ['id', 'product_id', 'shift_id'],
    );
    for (final row in rows) {
      final productId = (row['product_id'] as num?)?.toInt();
      final shiftId = (row['shift_id'] as num?)?.toInt();
      final values = <String, Object?>{};
      final productCloudId = await _cloudIdForLocalRow(
        db,
        'products',
        productId,
      );
      if (productCloudId != null) values['product_cloud_id'] = productCloudId;
      final shiftCloudId = await _cloudIdForLocalRow(db, 'shifts', shiftId);
      if (shiftCloudId != null) values['shift_cloud_id'] = shiftCloudId;
      if (values.isNotEmpty) {
        await db.update(
          'sales',
          values,
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }
  }

  Future<void> _backfillShiftReadingCloudRelationships(
    DatabaseExecutor db,
  ) async {
    final rows = await db.query('shift_readings', columns: ['id', 'shift_id']);
    for (final row in rows) {
      final shiftId = (row['shift_id'] as num?)?.toInt();
      final shiftCloudId = await _cloudIdForLocalRow(db, 'shifts', shiftId);
      if (shiftCloudId == null) continue;
      await db.update(
        'shift_readings',
        {'shift_cloud_id': shiftCloudId},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  Future<String?> _cloudIdForLocalRow(
    DatabaseExecutor db,
    String tableName,
    int? localId,
  ) async {
    if (localId == null) return null;
    final rows = await db.query(
      tableName,
      columns: ['cloud_id'],
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final cloudId = rows.first['cloud_id']?.toString().trim() ?? '';
    return cloudId.isEmpty ? null : cloudId;
  }

  String _newCloudId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_products_barcode_nocase
      ON products(barcode COLLATE NOCASE)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sales_created_at_id
      ON sales(created_at DESC, id DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sales_product_id
      ON sales(product_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sales_voided_at
      ON sales(voided_at)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sales_shift_id
      ON sales(shift_id)
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_shifts_one_open
      ON shifts(status)
      WHERE status = 'open'
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_shifts_opened_at
      ON shifts(opened_at DESC, id DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_shift_readings_shift_created
      ON shift_readings(shift_id, created_at DESC, id DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_users_pin_hash_role_created_at
      ON users(pin_hash, role, created_at)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_users_role_created_at
      ON users(role, created_at DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_audit_logs_timestamp
      ON audit_logs(timestamp DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_audit_logs_user_action
      ON audit_logs(user, action)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_queue_status_updated
      ON sync_queue(status, updated_at)
    ''');
  }

  Future<void> _ensureProductSchema(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(products)');
    final hasDescription = columns.cast<Map<String, Object?>>().any(
      (column) => column['name'] == 'description',
    );
    final columnNames = columns
        .cast<Map<String, Object?>>()
        .map((column) => column['name'])
        .toSet();

    if (!hasDescription) {
      await db.execute('ALTER TABLE products ADD COLUMN description TEXT');
    }
    if (!columnNames.contains('pending_delete')) {
      await db.execute(
        'ALTER TABLE products ADD COLUMN pending_delete INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!columnNames.contains('pending_delete_at')) {
      await db.execute(
        'ALTER TABLE products ADD COLUMN pending_delete_at TEXT',
      );
    }
    if (!columnNames.contains('discount_percent')) {
      await db.execute('ALTER TABLE products ADD COLUMN discount_percent REAL');
    }
    if (!columnNames.contains('discount_enabled')) {
      await db.execute(
        'ALTER TABLE products ADD COLUMN discount_enabled INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  Future<void> ensureSalesSchema() async {
    final db = await database;
    await _ensureSalesSchema(db);
  }

  Future<void> _ensureSalesSchema(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(sales)');
    final columnNames = columns
        .cast<Map<String, Object?>>()
        .map((column) => column['name'])
        .toSet();

    if (!columnNames.contains('image_url')) {
      await db.execute('ALTER TABLE sales ADD COLUMN image_url TEXT');
    }
    if (!columnNames.contains('cost_price')) {
      await db.execute('ALTER TABLE sales ADD COLUMN cost_price REAL');
    }
    if (!columnNames.contains('voided_at')) {
      await db.execute('ALTER TABLE sales ADD COLUMN voided_at TEXT');
    }
    if (!columnNames.contains('voided_by')) {
      await db.execute('ALTER TABLE sales ADD COLUMN voided_by TEXT');
    }
    if (!columnNames.contains('void_reason')) {
      await db.execute('ALTER TABLE sales ADD COLUMN void_reason TEXT');
    }
    if (!columnNames.contains('completion_due_at')) {
      await db.execute('ALTER TABLE sales ADD COLUMN completion_due_at TEXT');
    }
    if (!columnNames.contains('completed_at')) {
      await db.execute('ALTER TABLE sales ADD COLUMN completed_at TEXT');
      await db.execute('''
        UPDATE sales
        SET completed_at = created_at
        WHERE completed_at IS NULL OR completed_at = ''
      ''');
    }
    if (!columnNames.contains('receipt_number')) {
      await db.execute('ALTER TABLE sales ADD COLUMN receipt_number TEXT');
    }
    if (!columnNames.contains('receipt_subtotal')) {
      await db.execute('ALTER TABLE sales ADD COLUMN receipt_subtotal REAL');
    }
    if (!columnNames.contains('receipt_discount_amount')) {
      await db.execute(
        'ALTER TABLE sales ADD COLUMN receipt_discount_amount REAL',
      );
    }
    if (!columnNames.contains('receipt_discount_type')) {
      await db.execute(
        'ALTER TABLE sales ADD COLUMN receipt_discount_type TEXT',
      );
    }
    if (!columnNames.contains('receipt_discount_value')) {
      await db.execute(
        'ALTER TABLE sales ADD COLUMN receipt_discount_value REAL',
      );
    }
    if (!columnNames.contains('original_price')) {
      await db.execute('ALTER TABLE sales ADD COLUMN original_price REAL');
      await db.execute('''
        UPDATE sales
        SET original_price = price
        WHERE original_price IS NULL
      ''');
    }
    if (!columnNames.contains('product_discount_percent')) {
      await db.execute(
        'ALTER TABLE sales ADD COLUMN product_discount_percent REAL',
      );
    }
    if (!columnNames.contains('product_discount_amount')) {
      await db.execute(
        'ALTER TABLE sales ADD COLUMN product_discount_amount REAL',
      );
    }
    if (!columnNames.contains('shift_id')) {
      await db.execute('ALTER TABLE sales ADD COLUMN shift_id INTEGER');
    }
    await db.execute('''
      UPDATE sales
      SET receipt_number =
        'R-' || replace(
          replace(
            replace(
              replace(substr(created_at, 1, 19), '-', ''),
              ':',
              ''
            ),
            'T',
            '-'
          ),
          ' ',
          '-'
        )
      WHERE receipt_number IS NULL
        OR receipt_number = ''
        OR receipt_number = 'R-' || id
    ''');
  }

  String generateReceiptNumber([DateTime? value]) {
    final timestamp = (value ?? DateTime.now()).toLocal();
    final date =
        '${timestamp.year.toString().padLeft(4, '0')}'
        '${timestamp.month.toString().padLeft(2, '0')}'
        '${timestamp.day.toString().padLeft(2, '0')}';
    final time =
        '${timestamp.hour.toString().padLeft(2, '0')}'
        '${timestamp.minute.toString().padLeft(2, '0')}'
        '${timestamp.second.toString().padLeft(2, '0')}';
    final suffix = timestamp.microsecondsSinceEpoch
        .remainder(1000000)
        .toString()
        .padLeft(6, '0');
    return 'R-$date-$time-$suffix';
  }

  Future<void> ensureShiftSchema() async {
    final db = await database;
    await _ensureSalesSchema(db);
    await _createShiftsTable(db);
    await _createShiftReadingsTable(db);
    await _createIndexes(db);
  }

  Future<Map<String, Object?>?> getOpenShift() async {
    final db = await database;
    await ensureShiftSchema();
    final rows = await db.rawQuery(
      '''
      SELECT
        shifts.*,
        COALESCE(NULLIF(opened_user.full_name, ''), shifts.opened_by) AS opened_by_display_name,
        COALESCE(NULLIF(closed_user.full_name, ''), shifts.closed_by) AS closed_by_display_name
      FROM shifts
      LEFT JOIN users AS opened_user ON opened_user.username = shifts.opened_by
      LEFT JOIN users AS closed_user ON closed_user.username = shifts.closed_by
      WHERE shifts.status = ?
      ORDER BY shifts.opened_at DESC, shifts.id DESC
      LIMIT 1
      ''',
      ['open'],
    );
    if (rows.isEmpty) return null;
    return Map<String, Object?>.from(rows.first);
  }

  Future<Map<String, Object?>> requireOpenShiftForCheckout() async {
    final shift = await getOpenShift();
    if (shift == null) {
      throw Exception('Open a shift before completing sales.');
    }
    return shift;
  }

  Future<int> openShift({
    required double openingCash,
    required String openedBy,
  }) async {
    final db = await database;
    await ensureShiftSchema();
    final existing = await getOpenShift();
    if (existing != null) {
      throw Exception('A shift is already open.');
    }

    final now = DateTime.now().toIso8601String();
    final row = {
      'status': 'open',
      'opened_by': _normalizeActor(openedBy),
      'opened_at': now,
      'opening_cash': openingCash,
      'closed_by': null,
      'closed_at': null,
      'closing_cash': null,
      'expected_cash': null,
      'over_short': null,
      'z_reading_number': null,
    };
    final id = await db.insert('shifts', row);
    await queueSyncUpsert('shifts', {...row, 'id': id});
    unawaited(syncPendingChanges());
    return id;
  }

  Future<Map<String, Object?>> createXReading({
    required int shiftId,
    required String createdBy,
  }) async {
    final db = await database;
    await ensureShiftSchema();
    await completeDueSales();
    return await _createShiftReading(
      db,
      shiftId: shiftId,
      type: 'x',
      createdBy: createdBy,
    );
  }

  Future<Map<String, Object?>> closeShiftWithZReading({
    required int shiftId,
    required double countedCash,
    required String closedBy,
  }) async {
    final db = await database;
    await ensureShiftSchema();
    await completeDueSales();

    late Map<String, Object?> reading;
    await db.transaction((txn) async {
      final shift = await _shiftById(txn, shiftId);
      if (shift == null) throw Exception('Shift was not found.');
      if (shift['status']?.toString() != 'open') {
        throw Exception('Shift is already closed.');
      }

      reading = await _createShiftReading(
        txn,
        shiftId: shiftId,
        type: 'z',
        createdBy: closedBy,
        countedCash: countedCash,
      );
      final now =
          reading['created_at']?.toString() ?? DateTime.now().toIso8601String();
      final updatedShift = {
        ...shift,
        'status': 'closed',
        'closed_by': _normalizeActor(closedBy),
        'closed_at': now,
        'closing_cash': countedCash,
        'expected_cash': reading['expected_cash'],
        'over_short': reading['over_short'],
        'z_reading_number': _generateZReadingNumber(DateTime.parse(now)),
      };
      await txn.update(
        'shifts',
        updatedShift,
        where: 'id = ?',
        whereArgs: [shiftId],
      );
      await queueSyncUpsert('shifts', updatedShift, executor: txn);
    });
    unawaited(syncPendingChanges());
    return reading;
  }

  Future<List<Map<String, Object?>>> getShiftReadings({int? shiftId}) async {
    final db = await database;
    await ensureShiftSchema();
    return await db.rawQuery('''
      SELECT
        shift_readings.*,
        COALESCE(NULLIF(users.full_name, ''), shift_readings.created_by) AS created_by_display_name
      FROM shift_readings
      LEFT JOIN users ON users.username = shift_readings.created_by
      ${shiftId == null ? '' : 'WHERE shift_readings.shift_id = ?'}
      ORDER BY shift_readings.created_at DESC, shift_readings.id DESC
      ''', shiftId == null ? const [] : [shiftId]);
  }

  Future<List<Map<String, Object?>>> getShiftHistory({int limit = 30}) async {
    final db = await database;
    await ensureShiftSchema();
    return await db.rawQuery(
      '''
      SELECT
        shifts.*,
        COALESCE(NULLIF(opened_user.full_name, ''), shifts.opened_by) AS opened_by_display_name,
        COALESCE(NULLIF(closed_user.full_name, ''), shifts.closed_by) AS closed_by_display_name
      FROM shifts
      LEFT JOIN users AS opened_user ON opened_user.username = shifts.opened_by
      LEFT JOIN users AS closed_user ON closed_user.username = shifts.closed_by
      ORDER BY shifts.opened_at DESC, shifts.id DESC
      LIMIT ?
      ''',
      [limit],
    );
  }

  Future<Map<String, Object?>> getShiftSummary(int shiftId) async {
    final db = await database;
    await ensureShiftSchema();
    final shift = await _shiftById(db, shiftId);
    if (shift == null) throw Exception('Shift was not found.');
    final totals = await _shiftSalesTotals(db, shiftId);
    return {...shift, ...totals};
  }

  Future<Map<String, Object?>?> _shiftById(
    DatabaseExecutor db,
    int shiftId,
  ) async {
    final rows = await db.query(
      'shifts',
      where: 'id = ?',
      whereArgs: [shiftId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Map<String, Object?>.from(rows.first);
  }

  Future<Map<String, Object?>> _createShiftReading(
    DatabaseExecutor db, {
    required int shiftId,
    required String type,
    required String createdBy,
    double? countedCash,
  }) async {
    final shift = await _shiftById(db, shiftId);
    if (shift == null) throw Exception('Shift was not found.');
    final totals = await _shiftSalesTotals(db, shiftId);
    final openingCash = (shift['opening_cash'] as num?)?.toDouble() ?? 0;
    final salesTotal = (totals['sales_total'] as num?)?.toDouble() ?? 0;
    final expectedCash = openingCash + salesTotal;
    final overShort = countedCash == null ? null : countedCash - expectedCash;
    final row = {
      'shift_id': shiftId,
      'type': type,
      'created_by': _normalizeActor(createdBy),
      'created_at': DateTime.now().toIso8601String(),
      'opening_cash': openingCash,
      'sales_total': salesTotal,
      'void_total': (totals['void_total'] as num?)?.toDouble() ?? 0,
      'receipt_count': (totals['receipt_count'] as num?)?.toInt() ?? 0,
      'item_count': (totals['item_count'] as num?)?.toInt() ?? 0,
      'expected_cash': expectedCash,
      'counted_cash': countedCash,
      'over_short': overShort,
    };
    final id = await db.insert('shift_readings', row);
    final inserted = {...row, 'id': id};
    await queueSyncUpsert('shift_readings', inserted, executor: db);
    return inserted;
  }

  Future<Map<String, Object?>> _shiftSalesTotals(
    DatabaseExecutor db,
    int shiftId,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN is_voided = 0 THEN net_total ELSE 0 END), 0) AS sales_total,
        COALESCE(SUM(CASE WHEN is_voided = 1 THEN net_total ELSE 0 END), 0) AS void_total,
        COALESCE(SUM(CASE WHEN is_voided = 0 THEN quantity ELSE 0 END), 0) AS item_count,
        COALESCE(SUM(CASE WHEN is_voided = 0 THEN 1 ELSE 0 END), 0) AS receipt_count
      FROM (
        SELECT
          SUM(total) - MAX(COALESCE(receipt_discount_amount, 0)) AS net_total,
          SUM(quantity) AS quantity,
          CASE WHEN MAX(COALESCE(voided_at, '')) = '' THEN 0 ELSE 1 END AS is_voided
        FROM sales
        WHERE shift_id = ?
        GROUP BY COALESCE(NULLIF(receipt_number, ''), substr(created_at, 1, 19))
      )
      ''',
      [shiftId],
    );
    if (rows.isEmpty) {
      return {
        'sales_total': 0.0,
        'void_total': 0.0,
        'item_count': 0,
        'receipt_count': 0,
      };
    }
    final row = rows.first;
    return {
      'sales_total': (row['sales_total'] as num?)?.toDouble() ?? 0.0,
      'void_total': (row['void_total'] as num?)?.toDouble() ?? 0.0,
      'item_count': (row['item_count'] as num?)?.toInt() ?? 0,
      'receipt_count': (row['receipt_count'] as num?)?.toInt() ?? 0,
    };
  }

  String _generateZReadingNumber(DateTime value) {
    final local = value.toLocal();
    return 'Z-${local.year.toString().padLeft(4, '0')}'
        '${local.month.toString().padLeft(2, '0')}'
        '${local.day.toString().padLeft(2, '0')}-'
        '${local.hour.toString().padLeft(2, '0')}'
        '${local.minute.toString().padLeft(2, '0')}'
        '${local.second.toString().padLeft(2, '0')}';
  }

  String _normalizeActor(String value) {
    final sanitized = _sanitizeAuditText(value, maxLength: 80);
    return sanitized.trim().isEmpty ? 'unknown' : sanitized.trim();
  }

  Future<void> recordAuditLog({
    required String user,
    required String action,
    String? details,
  }) async {
    final db = await database;
    await _createAuditLogTable(db);
    await _createSyncQueueTable(db);

    final row = {
      'user': user.trim().isEmpty ? 'unknown' : user.trim().toLowerCase(),
      'action': action.trim(),
      'details': details?.trim(),
      'timestamp': DateTime.now().toIso8601String(),
    };
    final id = await db.insert('audit_logs', row);
    await queueSyncUpsert('audit_logs', {...row, 'id': id});
  }

  Future<void> queueSyncUpsert(
    String tableName,
    Map<String, Object?> row, {
    DatabaseExecutor? executor,
  }) async {
    final localId = row['id']?.toString();
    if (localId == null || localId.isEmpty) return;

    final db = executor ?? await database;
    await _createSyncQueueTable(db);
    final payload = await _rowWithCloudSyncIdentity(db, tableName, row);
    await _queueSyncEvent(
      db,
      tableName: tableName,
      localId: localId,
      operation: 'upsert',
      payload: payload,
    );
  }

  Future<void> queueSyncDelete(
    String tableName,
    Object localId,
    Map<String, Object?> oldRow, {
    DatabaseExecutor? executor,
    bool forceCloudDelete = false,
  }) async {
    final db = executor ?? await database;
    await _createSyncQueueTable(db);
    final rowWithIdentity = await _rowWithCloudSyncIdentity(
      db,
      tableName,
      oldRow,
      persist: false,
    );
    final payload = forceCloudDelete
        ? <String, Object?>{...rowWithIdentity, '_force_cloud_delete': true}
        : rowWithIdentity;
    await _queueSyncEvent(
      db,
      tableName: tableName,
      localId: localId.toString(),
      operation: 'delete',
      payload: payload,
    );
  }

  Future<void> _queueSyncEvent(
    DatabaseExecutor db, {
    required String tableName,
    required String localId,
    required String operation,
    required Map<String, Object?> payload,
  }) async {
    final now = DateTime.now().toIso8601String();
    final cloudId = payload['cloud_id']?.toString().trim() ?? '';
    if (cloudId.isEmpty) {
      throw Exception(
        'Cloud sync paused. Missing cloud_id for $tableName $localId, so local data was kept safe. Reopen the app to finish migration, then try again.',
      );
    }
    final queueKey = '$tableName:$cloudId';
    final existing = await db.query(
      'sync_queue',
      columns: ['cloud_revision', 'created_at'],
      where: 'queue_key = ?',
      whereArgs: [queueKey],
      limit: 1,
    );
    final cloudRevision = existing.isEmpty
        ? 0
        : (existing.first['cloud_revision'] as num?)?.toInt() ?? 0;
    final values = {
      'table_name': tableName,
      'local_id': localId,
      'cloud_id': cloudId,
      'operation': operation,
      'payload': jsonEncode(payload),
      'base_revision': cloudRevision,
      'cloud_revision': cloudRevision,
      'status': 'pending',
      'attempts': 0,
      'last_error': null,
      'conflict_details': null,
      'next_retry_at': null,
      'updated_at': now,
      'synced_at': null,
    };

    if (existing.isEmpty) {
      await db.insert('sync_queue', {
        'queue_key': queueKey,
        ...values,
        'created_at': now,
      });
      return;
    }

    await db.update(
      'sync_queue',
      values,
      where: 'queue_key = ?',
      whereArgs: [queueKey],
    );
  }

  Future<Map<String, Object?>> _rowWithCloudSyncIdentity(
    DatabaseExecutor db,
    String tableName,
    Map<String, Object?> row, {
    bool persist = true,
  }) async {
    final localId = (row['id'] as num?)?.toInt();
    final enriched = <String, Object?>{...row};
    var cloudId = enriched['cloud_id']?.toString().trim() ?? '';
    if (cloudId.isEmpty) {
      cloudId = _newCloudId();
      enriched['cloud_id'] = cloudId;
      if (persist && localId != null) {
        await db.update(
          tableName,
          {'cloud_id': cloudId},
          where: 'id = ?',
          whereArgs: [localId],
        );
      }
    }

    if (tableName == 'sales') {
      final productId = (enriched['product_id'] as num?)?.toInt();
      final shiftId = (enriched['shift_id'] as num?)?.toInt();
      final values = <String, Object?>{};
      final productCloudId = await _cloudIdForLocalRow(
        db,
        'products',
        productId,
      );
      if (productCloudId != null) {
        enriched['product_cloud_id'] = productCloudId;
        values['product_cloud_id'] = productCloudId;
      }
      final shiftCloudId = await _cloudIdForLocalRow(db, 'shifts', shiftId);
      if (shiftCloudId != null) {
        enriched['shift_cloud_id'] = shiftCloudId;
        values['shift_cloud_id'] = shiftCloudId;
      }
      if (persist && values.isNotEmpty && localId != null) {
        await db.update('sales', values, where: 'id = ?', whereArgs: [localId]);
      }
    } else if (tableName == 'shift_readings') {
      final shiftId = (enriched['shift_id'] as num?)?.toInt();
      final shiftCloudId = await _cloudIdForLocalRow(db, 'shifts', shiftId);
      if (shiftCloudId != null) {
        enriched['shift_cloud_id'] = shiftCloudId;
        if (persist && localId != null) {
          await db.update(
            'shift_readings',
            {'shift_cloud_id': shiftCloudId},
            where: 'id = ?',
            whereArgs: [localId],
          );
        }
      }
    }

    return enriched;
  }

  Future<int> syncPendingChanges({
    int limit = 100,
    int maxBatches = 100,
    bool forceRetry = false,
    void Function(int synced, int total, String status)? onProgress,
  }) async {
    if (_syncInProgress || _cloudRestoreInProgress) return 0;
    _syncInProgress = true;
    final db = await database;

    try {
      await _createSyncQueueTable(db);

      var syncedTotal = 0;
      final total = await pendingSyncCount();
      onProgress?.call(syncedTotal, total, 'Preparing sync');
      const service = SupabaseSyncService();

      for (var batch = 0; batch < maxBatches; batch++) {
        final now = DateTime.now().toIso8601String();
        final pending = await db.query(
          'sync_queue',
          where: forceRetry
              ? 'status IN (?, ?, ?)'
              : '''
            status IN (?, ?)
            AND (next_retry_at IS NULL OR next_retry_at = '' OR next_retry_at <= ?)
          ''',
          whereArgs: forceRetry
              ? ['pending', 'failed', 'conflict']
              : ['pending', 'failed', now],
          orderBy: 'updated_at ASC',
          limit: limit,
        );
        if (pending.isEmpty) return syncedTotal;

        onProgress?.call(
          syncedTotal,
          total,
          'Uploading batch ${batch + 1} (${pending.length} rows)',
        );
        try {
          final pendingRows = pending.cast<Map<String, Object?>>();
          final results = await service.uploadEvents(pendingRows);
          for (var index = 0; index < pendingRows.length; index += 1) {
            final row = pendingRows[index];
            final result = results[index];
            final syncedAt = DateTime.now().toIso8601String();
            if (result.conflicted) {
              await _markSyncQueueConflict(
                db,
                queueRowId: row['id'],
                queueKey: row['queue_key']?.toString(),
                revision: result.revision,
                message: result.message ?? 'Cloud row changed.',
                updatedAt: syncedAt,
              );
              onProgress?.call(
                syncedTotal,
                total,
                'Conflict found for ${row['table_name']} ${row['local_id']}',
              );
              continue;
            }
            await _markSyncQueueSynced(
              db,
              queueRowId: row['id'],
              queueKey: row['queue_key']?.toString(),
              revision: result.revision,
              syncedAt: syncedAt,
            );
            syncedTotal += 1;
            onProgress?.call(
              syncedTotal,
              total,
              'Uploaded $syncedTotal of $total',
            );
          }
        } catch (e) {
          final failedAt = DateTime.now();
          final message = e.toString().replaceFirst(
            RegExp(r'^Exception:\s*'),
            '',
          );
          final retryAt = failedAt.add(_syncRetryDelay(pending));
          final ids = pending.map((row) => row['id']).toList();
          await db.rawUpdate(
            '''
            UPDATE sync_queue
            SET status = ?,
                attempts = attempts + 1,
                last_error = ?,
                updated_at = ?,
                next_retry_at = ?
            WHERE id IN (${List.filled(ids.length, '?').join(',')})
              AND status IN (?, ?, ?)
            ''',
            [
              'failed',
              message,
              failedAt.toIso8601String(),
              retryAt.toIso8601String(),
              ...ids,
              'pending',
              'failed',
              'conflict',
            ],
          );
          onProgress?.call(
            syncedTotal,
            total,
            'Batch failed. Retry after ${_formatRetryTime(retryAt)}. $message',
          );
          return syncedTotal;
        }
      }

      return syncedTotal;
    } finally {
      _syncInProgress = false;
    }
  }

  Future<void> _markSyncQueueConflict(
    Database db, {
    required Object? queueRowId,
    required String? queueKey,
    required int revision,
    required String message,
    required String updatedAt,
  }) async {
    final values = {
      'status': 'conflict',
      'cloud_revision': revision,
      'last_error': 'Sync conflict: $message',
      'conflict_details': message,
      'updated_at': updatedAt,
      'next_retry_at': null,
    };

    final updated = await db.update(
      'sync_queue',
      values,
      where: 'id = ?',
      whereArgs: [queueRowId],
    );
    if (updated > 0 || queueKey == null || queueKey.isEmpty) return;

    await db.update(
      'sync_queue',
      values,
      where: 'queue_key = ?',
      whereArgs: [queueKey],
    );
  }

  Future<void> _markSyncQueueSynced(
    Database db, {
    required Object? queueRowId,
    required String? queueKey,
    required int revision,
    required String syncedAt,
  }) async {
    final values = {
      'status': 'synced',
      'base_revision': revision,
      'cloud_revision': revision,
      'synced_at': syncedAt,
      'updated_at': syncedAt,
      'last_error': null,
      'conflict_details': null,
      'next_retry_at': null,
    };

    final updated = await db.update(
      'sync_queue',
      values,
      where: 'id = ?',
      whereArgs: [queueRowId],
    );
    if (updated > 0 || queueKey == null || queueKey.isEmpty) return;

    await db.update(
      'sync_queue',
      values,
      where: 'queue_key = ?',
      whereArgs: [queueKey],
    );
  }

  Duration _syncRetryDelay(List<Map<String, Object?>> rows) {
    final maxAttempts = rows
        .map((row) => (row['attempts'] as num?)?.toInt() ?? 0)
        .fold<int>(0, (max, value) => value > max ? value : max);
    final seconds = (30 * (maxAttempts + 1)).clamp(30, 300).toInt();
    return Duration(seconds: seconds);
  }

  String _formatRetryTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  Future<int> pendingSyncCount() async {
    final db = await database;
    await _createSyncQueueTable(db);
    final count = Sqflite.firstIntValue(
      await db.rawQuery("SELECT COUNT(*) FROM sync_queue WHERE status != ?", [
        'synced',
      ]),
    );
    return count ?? 0;
  }

  Future<int> conflictedSyncCount() async {
    final db = await database;
    await _createSyncQueueTable(db);
    final count = Sqflite.firstIntValue(
      await db.rawQuery("SELECT COUNT(*) FROM sync_queue WHERE status = ?", [
        'conflict',
      ]),
    );
    return count ?? 0;
  }

  Future<String?> lastSyncError() async {
    final db = await database;
    await _createSyncQueueTable(db);
    final rows = await db.query(
      'sync_queue',
      columns: ['last_error'],
      where:
          "status != ? AND last_error IS NOT NULL AND TRIM(last_error) != ''",
      whereArgs: ['synced'],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['last_error']?.toString();
  }

  Future<void> queueLocalSnapshotForSync() async {
    final db = await database;
    await _ensureCloudIdentitySchema(db);

    final products = await db.query('products');
    for (final row in products) {
      await _queueSnapshotUpsert(db, 'products', row);
    }

    final sales = await db.query('sales');
    for (final row in sales) {
      await _queueSnapshotUpsert(db, 'sales', row);
    }

    final shifts = await db.query('shifts');
    for (final row in shifts) {
      await _queueSnapshotUpsert(db, 'shifts', row);
    }

    final shiftReadings = await db.query('shift_readings');
    for (final row in shiftReadings) {
      await _queueSnapshotUpsert(db, 'shift_readings', row);
    }

    final users = await db.query('users');
    for (final row in users) {
      await _queueSnapshotUpsert(db, 'users', row);
    }

    final auditLogs = await db.query('audit_logs');
    for (final row in auditLogs) {
      await _queueSnapshotUpsert(db, 'audit_logs', row);
    }

    const service = SupabaseSyncService();
    await service.deleteLegacySalesImageFolder();
  }

  Future<T> runWithCloudRestoreGuard<T>(Future<T> Function() action) async {
    while (_cloudRestoreInProgress) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    _cloudRestoreInProgress = true;
    try {
      while (_syncInProgress) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return await action();
    } finally {
      _cloudRestoreInProgress = false;
    }
  }

  Future<int> pullCloudSnapshotToLocal({
    void Function(int imported, int total, String status)? onProgress,
  }) async {
    final db = await database;
    await _ensureCloudIdentitySchema(db);

    const service = SupabaseSyncService();
    onProgress?.call(0, 0, 'Downloading cloud data');
    final snapshot = _prepareCloudSnapshotForRestore(
      await service.downloadStoreSnapshot(),
    );
    final imageDirPath = await productImagesDirectoryPath();
    await Directory(imageDirPath).create(recursive: true);

    final total = snapshot.values.fold<int>(
      0,
      (sum, rows) => sum + rows.length,
    );
    var imported = 0;

    await db.transaction((txn) async {
      await _clearLocalMirrorBeforeCloudRestore(txn);

      imported += await _importCloudRows(
        txn,
        'products',
        snapshot['products'] ?? const [],
        (row) => _cloudProductToLocalRow(row, service, imageDirPath),
      );
      onProgress?.call(imported, total, 'Restored products');

      imported += await _importCloudRows(
        txn,
        'users',
        snapshot['users'] ?? const [],
        _cloudUserToLocalRow,
      );
      onProgress?.call(imported, total, 'Restored users');

      imported += await _importCloudRows(
        txn,
        'sales',
        snapshot['sales'] ?? const [],
        _cloudSaleToLocalRow,
      );
      onProgress?.call(imported, total, 'Restored sales');

      imported += await _importCloudRows(
        txn,
        'shifts',
        snapshot['shifts'] ?? const [],
        _cloudShiftToLocalRow,
      );
      onProgress?.call(imported, total, 'Restored shifts');

      imported += await _importCloudRows(
        txn,
        'shift_readings',
        snapshot['shift_readings'] ?? const [],
        _cloudShiftReadingToLocalRow,
      );
      onProgress?.call(imported, total, 'Restored shift readings');

      imported += await _importCloudRows(
        txn,
        'audit_logs',
        snapshot['audit_logs'] ?? const [],
        _cloudAuditLogToLocalRow,
      );
      onProgress?.call(imported, total, 'Restored audit log');

      await _relinkCloudRestoredRelationships(txn);
      await _markCloudSnapshotSynced(snapshot, executor: txn);
    });

    onProgress?.call(imported, total, 'Cloud data restored');
    return imported;
  }

  Map<String, List<Map<String, dynamic>>> _prepareCloudSnapshotForRestore(
    Map<String, List<Map<String, dynamic>>> snapshot,
  ) {
    final prepared = <String, List<Map<String, dynamic>>>{};
    for (final entry in snapshot.entries) {
      prepared[entry.key] = _dedupeCloudRowsByIdentity(entry.value);
    }

    prepared['users'] = _dedupeCloudRowsByField(
      prepared['users'] ?? const [],
      'username',
    );

    final shifts = prepared['shifts'] ?? const [];
    final openShifts = shifts
        .where((row) => _cloudRowString(row, 'status').toLowerCase() == 'open')
        .toList();
    if (openShifts.length > 1) {
      openShifts.sort(_newestCloudRowFirst);
      final keptOpenShift = openShifts.first;
      final keptCloudId = _cloudRowString(keptOpenShift, 'cloud_id');
      final skippedOpenShiftIds = openShifts
          .skip(1)
          .map((row) => _cloudRowString(row, 'cloud_id'))
          .where((cloudId) => cloudId.isNotEmpty)
          .toSet();

      prepared['shifts'] = shifts
          .where((row) {
            final status = _cloudRowString(row, 'status').toLowerCase();
            if (status != 'open') return true;
            return _cloudRowString(row, 'cloud_id') == keptCloudId;
          })
          .toList(growable: false);

      if (skippedOpenShiftIds.isNotEmpty) {
        prepared['sales'] = (prepared['sales'] ?? const [])
            .where((row) {
              final shiftCloudId = _cloudRowString(row, 'shift_cloud_id');
              return shiftCloudId.isEmpty ||
                  !skippedOpenShiftIds.contains(shiftCloudId);
            })
            .toList(growable: false);

        prepared['shift_readings'] = (prepared['shift_readings'] ?? const [])
            .where((row) {
              final shiftCloudId = _cloudRowString(row, 'shift_cloud_id');
              return shiftCloudId.isNotEmpty &&
                  !skippedOpenShiftIds.contains(shiftCloudId);
            })
            .toList(growable: false);
      }
    }

    prepared['shift_readings'] = (prepared['shift_readings'] ?? const [])
        .where((row) {
          return _cloudRowString(row, 'shift_cloud_id').isNotEmpty;
        })
        .toList(growable: false);

    return prepared;
  }

  List<Map<String, dynamic>> _dedupeCloudRowsByIdentity(
    List<Map<String, dynamic>> rows,
  ) {
    final byCloudId = <String, Map<String, dynamic>>{};
    final withoutCloudId = <Map<String, dynamic>>[];
    for (final row in rows) {
      final cloudId = _cloudRowString(row, 'cloud_id');
      if (cloudId.isEmpty) {
        withoutCloudId.add(row);
        continue;
      }
      final existing = byCloudId[cloudId];
      if (existing == null || _newestCloudRowFirst(row, existing) < 0) {
        byCloudId[cloudId] = row;
      }
    }
    return [...byCloudId.values, ...withoutCloudId];
  }

  List<Map<String, dynamic>> _dedupeCloudRowsByField(
    List<Map<String, dynamic>> rows,
    String field,
  ) {
    final byField = <String, Map<String, dynamic>>{};
    final withoutField = <Map<String, dynamic>>[];
    for (final row in rows) {
      final value = _cloudRowString(row, field).toLowerCase();
      if (value.isEmpty) {
        withoutField.add(row);
        continue;
      }
      final existing = byField[value];
      if (existing == null || _newestCloudRowFirst(row, existing) < 0) {
        byField[value] = row;
      }
    }
    return [...byField.values, ...withoutField];
  }

  int _newestCloudRowFirst(
    Map<String, dynamic> left,
    Map<String, dynamic> right,
  ) {
    final leftRevision = (left['revision'] as num?)?.toInt() ?? 0;
    final rightRevision = (right['revision'] as num?)?.toInt() ?? 0;
    if (leftRevision != rightRevision) {
      return rightRevision.compareTo(leftRevision);
    }
    return _cloudRowTimestamp(right).compareTo(_cloudRowTimestamp(left));
  }

  DateTime _cloudRowTimestamp(Map<String, dynamic> row) {
    for (final key in const [
      'cloud_updated_at',
      'updated_at',
      'opened_at',
      'created_at',
    ]) {
      final value = _cloudRowString(row, key);
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _cloudRowString(Map<String, dynamic> row, String key) {
    final payload = _cloudPayloadMap(row);
    return _cloudNullableString(payload, row, key)?.trim() ?? '';
  }

  Future<void> _relinkCloudRestoredRelationships(DatabaseExecutor db) async {
    final sales = await db.query(
      'sales',
      columns: ['id', 'product_cloud_id', 'shift_cloud_id'],
      where:
          "(product_cloud_id IS NOT NULL AND TRIM(product_cloud_id) != '') OR "
          "(shift_cloud_id IS NOT NULL AND TRIM(shift_cloud_id) != '')",
    );
    for (final sale in sales) {
      final values = <String, Object?>{};
      final productCloudId = sale['product_cloud_id']?.toString().trim() ?? '';
      if (productCloudId.isNotEmpty) {
        final productId = await _localIdForCloudId(
          db,
          'products',
          productCloudId,
        );
        if (productId == null) {
          throw Exception(
            'Restore paused. A sale could not find its product, so your current local data was not changed.',
          );
        }
        values['product_id'] = productId;
      }
      final shiftCloudId = sale['shift_cloud_id']?.toString().trim() ?? '';
      if (shiftCloudId.isNotEmpty) {
        final shiftId = await _localIdForCloudId(db, 'shifts', shiftCloudId);
        if (shiftId == null) {
          values['shift_id'] = null;
        } else {
          values['shift_id'] = shiftId;
        }
      }
      if (values.isNotEmpty) {
        await db.update(
          'sales',
          values,
          where: 'id = ?',
          whereArgs: [sale['id']],
        );
      }
    }

    final readings = await db.query(
      'shift_readings',
      columns: ['id', 'shift_cloud_id'],
      where: "shift_cloud_id IS NOT NULL AND TRIM(shift_cloud_id) != ''",
    );
    for (final reading in readings) {
      final shiftCloudId = reading['shift_cloud_id']?.toString().trim() ?? '';
      final shiftId = await _localIdForCloudId(db, 'shifts', shiftCloudId);
      if (shiftId == null) {
        await db.delete(
          'shift_readings',
          where: 'id = ?',
          whereArgs: [reading['id']],
        );
        continue;
      }
      await db.update(
        'shift_readings',
        {'shift_id': shiftId},
        where: 'id = ?',
        whereArgs: [reading['id']],
      );
    }
  }

  Future<int?> _localIdForCloudId(
    DatabaseExecutor db,
    String tableName,
    String cloudId,
  ) async {
    final rows = await db.query(
      tableName,
      columns: ['id'],
      where: 'cloud_id = ?',
      whereArgs: [cloudId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['id'] as num?)?.toInt();
  }

  Future<void> _clearLocalMirrorBeforeCloudRestore(DatabaseExecutor db) async {
    await db.delete('sync_queue');
    await db.delete('shift_readings');
    await db.delete('shifts');
    await db.delete('sales');
    await db.delete('products');
    await db.delete('users');
    await db.delete('audit_logs');
  }

  Future<int> _importCloudRows(
    DatabaseExecutor db,
    String tableName,
    List<Map<String, dynamic>> cloudRows,
    FutureOr<Map<String, Object?>> Function(Map<String, dynamic>) mapper,
  ) async {
    var imported = 0;
    for (final cloudRow in cloudRows) {
      if (_shouldSkipCloudRestoreRow(tableName, cloudRow)) continue;
      final row = await mapper(cloudRow);
      await db.insert(
        tableName,
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      imported += 1;
    }
    return imported;
  }

  bool _shouldSkipCloudRestoreRow(
    String tableName,
    Map<String, dynamic> cloudRow,
  ) {
    if ((cloudRow['deleted_at']?.toString().trim() ?? '').isNotEmpty) {
      return true;
    }
    if (tableName != 'products') return false;

    final payload = _cloudPayloadMap(cloudRow);
    return _cloudBoolInt(payload, cloudRow, 'pending_delete') == 1;
  }

  Future<void> _markCloudSnapshotSynced(
    Map<String, List<Map<String, dynamic>>> snapshot, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await database;
    await _createSyncQueueTable(db);
    final syncedAt = DateTime.now().toIso8601String();

    for (final entry in snapshot.entries) {
      for (final cloudRow in entry.value) {
        final payload = _cloudPayloadMap(cloudRow);
        final cloudId = _cloudNullableString(payload, cloudRow, 'cloud_id');
        if (cloudId == null || cloudId.isEmpty) continue;
        final restoredLocalId = await _localIdForCloudId(
          db,
          entry.key,
          cloudId,
        );
        final localId =
            restoredLocalId?.toString() ?? cloudRow['local_id']?.toString();
        if (localId == null || localId.isEmpty) continue;
        await db.insert('sync_queue', {
          'queue_key': '${entry.key}:$cloudId',
          'table_name': entry.key,
          'local_id': localId,
          'cloud_id': cloudId,
          'operation': cloudRow['operation']?.toString() ?? 'upsert',
          'payload': jsonEncode(payload),
          'base_revision': (cloudRow['revision'] as num?)?.toInt() ?? 0,
          'cloud_revision': (cloudRow['revision'] as num?)?.toInt() ?? 0,
          'status': 'synced',
          'attempts': 0,
          'last_error': null,
          'conflict_details': null,
          'next_retry_at': null,
          'created_at':
              cloudRow['local_updated_at']?.toString() ??
              cloudRow['created_at']?.toString() ??
              syncedAt,
          'updated_at': syncedAt,
          'synced_at': syncedAt,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  }

  Future<Map<String, Object?>> _cloudProductToLocalRow(
    Map<String, dynamic> cloudRow,
    SupabaseSyncService service,
    String imageDirPath,
  ) async {
    final payload = _cloudPayloadMap(cloudRow);
    return {
      'cloud_id':
          _cloudNullableString(payload, cloudRow, 'cloud_id') ?? _newCloudId(),
      'barcode': _cloudString(payload, cloudRow, 'barcode'),
      'product_name': _cloudString(payload, cloudRow, 'product_name'),
      'category': _cloudNullableString(payload, cloudRow, 'category'),
      'description': _cloudNullableString(payload, cloudRow, 'description'),
      'price': _cloudNumber(payload, cloudRow, 'price'),
      'discount_percent': _cloudNullableNumber(
        payload,
        cloudRow,
        'discount_percent',
      ),
      'discount_enabled': _cloudBoolInt(payload, cloudRow, 'discount_enabled'),
      'cost_price': _cloudNumber(payload, cloudRow, 'cost_price'),
      'stock_quantity': _cloudInt(payload, cloudRow, 'stock_quantity'),
      'image_url': await _localImagePathFromCloud(
        _cloudNullableString(payload, cloudRow, 'image_url'),
        service,
        imageDirPath,
      ),
      'pending_delete': _cloudBoolInt(payload, cloudRow, 'pending_delete'),
      'pending_delete_at': _cloudNullableString(
        payload,
        cloudRow,
        'pending_delete_at',
      ),
      'created_at':
          _cloudNullableString(payload, cloudRow, 'created_at') ??
          DateTime.now().toIso8601String(),
      'updated_at':
          _cloudNullableString(payload, cloudRow, 'updated_at') ??
          cloudRow['local_updated_at']?.toString() ??
          DateTime.now().toIso8601String(),
    };
  }

  Map<String, Object?> _cloudUserToLocalRow(Map<String, dynamic> cloudRow) {
    final payload = _cloudPayloadMap(cloudRow);
    return {
      'cloud_id':
          _cloudNullableString(payload, cloudRow, 'cloud_id') ?? _newCloudId(),
      'username': _cloudString(payload, cloudRow, 'username'),
      'password_hash': _cloudString(payload, cloudRow, 'password_hash'),
      'pin_hash': _cloudNullableString(payload, cloudRow, 'pin_hash'),
      'full_name': _cloudNullableString(payload, cloudRow, 'full_name'),
      'email': _cloudNullableString(payload, cloudRow, 'email'),
      'role': _cloudNullableString(payload, cloudRow, 'role') ?? 'staff',
      'created_at':
          _cloudNullableString(payload, cloudRow, 'created_at') ??
          DateTime.now().toIso8601String(),
    };
  }

  Map<String, Object?> _cloudSaleToLocalRow(Map<String, dynamic> cloudRow) {
    final payload = _cloudPayloadMap(cloudRow);
    return {
      'cloud_id':
          _cloudNullableString(payload, cloudRow, 'cloud_id') ?? _newCloudId(),
      'product_id': _cloudInt(payload, cloudRow, 'local_product_id'),
      'product_cloud_id': _cloudNullableString(
        payload,
        cloudRow,
        'product_cloud_id',
      ),
      'product_name': _cloudString(payload, cloudRow, 'product_name'),
      'quantity': _cloudInt(payload, cloudRow, 'quantity'),
      'price': _cloudNumber(payload, cloudRow, 'price'),
      'original_price': _cloudNullableNumber(
        payload,
        cloudRow,
        'original_price',
      ),
      'product_discount_percent': _cloudNullableNumber(
        payload,
        cloudRow,
        'product_discount_percent',
      ),
      'product_discount_amount': _cloudNullableNumber(
        payload,
        cloudRow,
        'product_discount_amount',
      ),
      'cost_price': _cloudNullableNumber(payload, cloudRow, 'cost_price'),
      'total': _cloudNumber(payload, cloudRow, 'total'),
      'image_url': null,
      'voided_at': _cloudNullableString(payload, cloudRow, 'voided_at'),
      'voided_by':
          _cloudNullableString(payload, cloudRow, 'voided_by') ??
          _cloudNullableString(payload, cloudRow, 'local_voided_by'),
      'void_reason': _cloudNullableString(payload, cloudRow, 'void_reason'),
      'completion_due_at': _cloudNullableString(
        payload,
        cloudRow,
        'completion_due_at',
      ),
      'completed_at': _cloudNullableString(payload, cloudRow, 'completed_at'),
      'receipt_number': _cloudNullableString(
        payload,
        cloudRow,
        'receipt_number',
      ),
      'receipt_subtotal': _cloudNullableNumber(
        payload,
        cloudRow,
        'receipt_subtotal',
      ),
      'receipt_discount_amount': _cloudNullableNumber(
        payload,
        cloudRow,
        'receipt_discount_amount',
      ),
      'receipt_discount_type': _cloudNullableString(
        payload,
        cloudRow,
        'receipt_discount_type',
      ),
      'receipt_discount_value': _cloudNullableNumber(
        payload,
        cloudRow,
        'receipt_discount_value',
      ),
      'shift_id': _cloudNullableInt(payload, cloudRow, 'shift_id'),
      'shift_cloud_id': _cloudNullableString(
        payload,
        cloudRow,
        'shift_cloud_id',
      ),
      'created_at':
          _cloudNullableString(payload, cloudRow, 'created_at') ??
          DateTime.now().toIso8601String(),
    };
  }

  Map<String, Object?> _cloudShiftToLocalRow(Map<String, dynamic> cloudRow) {
    final payload = _cloudPayloadMap(cloudRow);
    return {
      'cloud_id':
          _cloudNullableString(payload, cloudRow, 'cloud_id') ?? _newCloudId(),
      'status': _cloudNullableString(payload, cloudRow, 'status') ?? 'open',
      'opened_by':
          _cloudNullableString(payload, cloudRow, 'opened_by') ?? 'unknown',
      'opened_at':
          _cloudNullableString(payload, cloudRow, 'opened_at') ??
          DateTime.now().toIso8601String(),
      'opening_cash': _cloudNumber(payload, cloudRow, 'opening_cash'),
      'closed_by': _cloudNullableString(payload, cloudRow, 'closed_by'),
      'closed_at': _cloudNullableString(payload, cloudRow, 'closed_at'),
      'closing_cash': _cloudNullableNumber(payload, cloudRow, 'closing_cash'),
      'expected_cash': _cloudNullableNumber(payload, cloudRow, 'expected_cash'),
      'over_short': _cloudNullableNumber(payload, cloudRow, 'over_short'),
      'z_reading_number': _cloudNullableString(
        payload,
        cloudRow,
        'z_reading_number',
      ),
    };
  }

  Map<String, Object?> _cloudShiftReadingToLocalRow(
    Map<String, dynamic> cloudRow,
  ) {
    final payload = _cloudPayloadMap(cloudRow);
    return {
      'cloud_id':
          _cloudNullableString(payload, cloudRow, 'cloud_id') ?? _newCloudId(),
      'shift_id': _cloudInt(payload, cloudRow, 'shift_id'),
      'shift_cloud_id': _cloudNullableString(
        payload,
        cloudRow,
        'shift_cloud_id',
      ),
      'type': _cloudNullableString(payload, cloudRow, 'type') ?? 'x',
      'created_by':
          _cloudNullableString(payload, cloudRow, 'created_by') ?? 'unknown',
      'created_at':
          _cloudNullableString(payload, cloudRow, 'created_at') ??
          DateTime.now().toIso8601String(),
      'opening_cash': _cloudNumber(payload, cloudRow, 'opening_cash'),
      'sales_total': _cloudNumber(payload, cloudRow, 'sales_total'),
      'void_total': _cloudNumber(payload, cloudRow, 'void_total'),
      'receipt_count': _cloudInt(payload, cloudRow, 'receipt_count'),
      'item_count': _cloudInt(payload, cloudRow, 'item_count'),
      'expected_cash': _cloudNumber(payload, cloudRow, 'expected_cash'),
      'counted_cash': _cloudNullableNumber(payload, cloudRow, 'counted_cash'),
      'over_short': _cloudNullableNumber(payload, cloudRow, 'over_short'),
    };
  }

  Map<String, Object?> _cloudAuditLogToLocalRow(Map<String, dynamic> cloudRow) {
    final payload = _cloudPayloadMap(cloudRow);
    return {
      'cloud_id':
          _cloudNullableString(payload, cloudRow, 'cloud_id') ?? _newCloudId(),
      'user':
          _cloudNullableString(payload, cloudRow, 'local_user') ??
          _cloudNullableString(payload, cloudRow, 'user') ??
          'unknown',
      'action': _cloudString(payload, cloudRow, 'action'),
      'details': _cloudNullableString(payload, cloudRow, 'details'),
      'timestamp':
          _cloudNullableString(payload, cloudRow, 'timestamp') ??
          DateTime.now().toIso8601String(),
    };
  }

  Map<String, Object?> _cloudPayloadMap(Map<String, dynamic> cloudRow) {
    final payload = cloudRow['payload'];
    if (payload is Map) {
      return Map<String, Object?>.from(payload);
    }
    if (payload is String && payload.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map) return Map<String, Object?>.from(decoded);
      } catch (_) {
        return <String, Object?>{};
      }
    }
    return <String, Object?>{};
  }

  String _cloudString(
    Map<String, Object?> payload,
    Map<String, dynamic> cloudRow,
    String key,
  ) {
    return _cloudNullableString(payload, cloudRow, key) ?? '';
  }

  String? _cloudNullableString(
    Map<String, Object?> payload,
    Map<String, dynamic> cloudRow,
    String key,
  ) {
    final value = payload.containsKey(key) ? payload[key] : cloudRow[key];
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  num _cloudNumber(
    Map<String, Object?> payload,
    Map<String, dynamic> cloudRow,
    String key,
  ) {
    final value = payload.containsKey(key) ? payload[key] : cloudRow[key];
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }

  num? _cloudNullableNumber(
    Map<String, Object?> payload,
    Map<String, dynamic> cloudRow,
    String key,
  ) {
    final value = payload.containsKey(key) ? payload[key] : cloudRow[key];
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '');
  }

  int _cloudInt(
    Map<String, Object?> payload,
    Map<String, dynamic> cloudRow,
    String key,
  ) {
    final value = payload.containsKey(key) ? payload[key] : cloudRow[key];
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int? _cloudNullableInt(
    Map<String, Object?> payload,
    Map<String, dynamic> cloudRow,
    String key,
  ) {
    final value = payload.containsKey(key) ? payload[key] : cloudRow[key];
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  int _cloudBoolInt(
    Map<String, Object?> payload,
    Map<String, dynamic> cloudRow,
    String key,
  ) {
    final value = payload.containsKey(key) ? payload[key] : cloudRow[key];
    if (value is bool) return value ? 1 : 0;
    if (value is num) return value == 0 ? 0 : 1;
    return value?.toString().toLowerCase() == 'true' ? 1 : 0;
  }

  Future<String?> _localImagePathFromCloud(
    String? imageReference,
    SupabaseSyncService service,
    String imageDirPath,
  ) async {
    final imagePath = imageReference?.trim();
    if (imagePath == null || imagePath.isEmpty) return null;
    if (imagePath.startsWith('http')) return imagePath;

    if (!imagePath.startsWith(SupabaseSyncService.cloudImagePrefix)) {
      return await File(imagePath).exists() ? imagePath : null;
    }

    final bytes = await service.downloadCloudImage(imagePath);
    if (bytes == null || bytes.isEmpty) return null;

    final fileName = service.cloudImageFileName(imagePath);
    final safeFileName = (fileName == null || fileName.trim().isEmpty)
        ? 'cloud_image_${DateTime.now().microsecondsSinceEpoch}.jpg'
        : fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    final targetPath = join(imageDirPath, safeFileName);
    await File(targetPath).writeAsBytes(bytes, flush: true);
    return targetPath;
  }

  Future<void> _queueSnapshotUpsert(
    DatabaseExecutor db,
    String tableName,
    Map<String, Object?> row,
  ) async {
    final localId = row['id']?.toString();
    if (localId == null || localId.isEmpty) return;

    final payload = await _rowWithCloudSyncIdentity(db, tableName, row);
    final cloudId = payload['cloud_id']?.toString().trim() ?? '';
    if (cloudId.isEmpty) return;

    final queueKey = '$tableName:$cloudId';
    final existing = await db.query(
      'sync_queue',
      columns: ['id', 'status', 'payload'],
      where: 'queue_key = ?',
      whereArgs: [queueKey],
      limit: 1,
    );
    if (existing.isNotEmpty &&
        !await _shouldRefreshSnapshotSync(tableName, row, existing.first)) {
      return;
    }

    await _queueSyncEvent(
      db,
      tableName: tableName,
      localId: localId,
      operation: 'upsert',
      payload: payload,
    );
  }

  Future<bool> _shouldRefreshSnapshotSync(
    String tableName,
    Map<String, Object?> row,
    Map<String, Object?> existingQueueRow,
  ) async {
    if (tableName != 'products') return false;
    if (existingQueueRow['status']?.toString() != 'synced') return false;

    final imagePath = row['image_url']?.toString().trim() ?? '';
    if (imagePath.isEmpty ||
        imagePath.startsWith('http') ||
        imagePath.startsWith(SupabaseSyncService.cloudImagePrefix)) {
      return false;
    }
    if (!await File(imagePath).exists()) return false;

    final payload = existingQueueRow['payload']?.toString() ?? '{}';
    final decoded = _decodeSyncPayload(payload);
    final syncedImagePath = decoded['image_url']?.toString().trim() ?? '';
    return !syncedImagePath.startsWith(SupabaseSyncService.cloudImagePrefix);
  }

  Map<String, Object?> _decodeSyncPayload(String payloadText) {
    try {
      final decoded = jsonDecode(payloadText);
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } catch (_) {
      return <String, Object?>{};
    }
    return <String, Object?>{};
  }

  Future<void> recordVoidSaleAudit({
    required String user,
    required Object saleId,
    String? details,
  }) {
    final payload = <String, Object?>{'sale_id': saleId.toString()};

    if (details != null && details.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(details);
        if (decoded is Map<String, dynamic>) {
          payload.addAll(decoded);
        } else {
          payload['details'] = details.trim();
        }
      } catch (_) {
        payload['details'] = details.trim();
      }
    }

    return recordAuditLog(
      user: user,
      action: 'void_sale',
      details: jsonEncode(payload),
    );
  }

  Future<List<Map<String, dynamic>>> getAuditLogs({int limit = 200}) async {
    final db = await database;
    await _createAuditLogTable(db);
    return db.query('audit_logs', orderBy: 'timestamp DESC', limit: limit);
  }

  String _auditDetails(Map<String, Object?> values) => jsonEncode(
    Map.fromEntries(values.entries.where((entry) => entry.value != null)),
  );

  String _sanitizeAuditText(
    String value, {
    int maxLength = 250,
    bool multiline = false,
  }) {
    final controlChars = multiline
        ? RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]')
        : RegExp(r'[\u0000-\u001F\u007F]');
    final sanitized = value
        .replaceAll(controlChars, ' ')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
    return sanitized.length <= maxLength
        ? sanitized
        : sanitized.substring(0, maxLength).trimRight();
  }

  // â”€â”€â”€ Password hashing â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  String _normalizeAuthUsername(String username) {
    return LoginInputValidator.sanitizeUsername(username);
  }

  String _sanitizeAuthSecret(String value, {int maxLength = 128}) {
    final sanitized = LoginInputValidator.sanitizePassword(value);
    return sanitized.length <= maxLength
        ? sanitized
        : sanitized.substring(0, maxLength);
  }

  String _normalizePin(String pin) {
    final digits = pin.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length <= 6 ? digits : digits.substring(0, 6);
  }

  bool _isValidPin(String pin) => _normalizePin(pin).length == 6;

  // â”€â”€â”€ Auth methods â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Returns the user map if credentials are valid, null otherwise.
  Future<Map<String, dynamic>?> login(String username, String password) async {
    final db = await database;
    final normalizedUsername = _normalizeAuthUsername(username);
    final normalizedPassword = _sanitizeAuthSecret(password);
    final isEmailLogin = LoginInputValidator.isEmail(normalizedUsername);
    if (!LoginInputValidator.isValidUsernameOrEmail(normalizedUsername) ||
        !LoginInputValidator.isValidPassword(normalizedPassword)) {
      await recordAuditLog(
        user: normalizedUsername.isEmpty ? 'unknown' : normalizedUsername,
        action: 'login_failed',
        details: _auditDetails({
          'method': 'password',
          'reason': 'invalid_input',
        }),
      );
      return null;
    }
    final hash = _hashPassword(normalizedPassword);

    final result = await db.query(
      'users',
      where: isEmailLogin
          ? '(LOWER(email) = ? OR username = ?) AND password_hash = ?'
          : 'username = ? AND password_hash = ?',
      whereArgs: isEmailLogin
          ? [normalizedUsername, normalizedUsername, hash]
          : [normalizedUsername, hash],
    );

    if (result.isNotEmpty) {
      await recordAuditLog(
        user: normalizedUsername,
        action: 'login',
        details: _auditDetails({'method': 'password', 'status': 'success'}),
      );
      return result.first;
    }

    await recordAuditLog(
      user: normalizedUsername.isEmpty ? 'unknown' : normalizedUsername,
      action: 'login_failed',
      details: _auditDetails({'method': 'password'}),
    );
    return null;
  }

  Future<Map<String, dynamic>?> loginWithPin(String pin) async {
    final db = await database;
    final normalizedPin = _normalizePin(pin);
    if (!_isValidPin(normalizedPin)) return null;
    final hash = _hashPassword(normalizedPin);

    final result = await db.query(
      'users',
      where: 'pin_hash = ?',
      whereArgs: [hash],
      orderBy: "CASE role WHEN 'admin' THEN 0 ELSE 1 END, created_at ASC",
      limit: 1,
    );

    if (result.isNotEmpty) {
      final user = result.first;
      await recordAuditLog(
        user: user['username']?.toString() ?? 'unknown',
        action: 'login',
        details: _auditDetails({'method': 'pin', 'status': 'success'}),
      );
      return user;
    }
    return null;
  }

  Future<Map<String, dynamic>?> verifyAdminPin(String pin) async {
    final db = await database;
    final normalizedPin = _normalizePin(pin);
    if (!_isValidPin(normalizedPin)) return null;

    final hash = _hashPassword(normalizedPin);

    final result = await db.query(
      'users',
      where: 'pin_hash = ? AND role = ?',
      whereArgs: [hash, 'admin'],
      limit: 1,
    );

    if (result.isEmpty) return null;
    return result.first;
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

  Future<bool> pinExists(String pin, {int? excludeUserId}) async {
    final db = await database;
    final normalizedPin = _normalizePin(pin);
    if (!_isValidPin(normalizedPin)) return false;
    final hash = _hashPassword(normalizedPin);
    final result = await db.query(
      'users',
      columns: ['id'],
      where: excludeUserId == null
          ? "pin_hash = ? AND pin_hash IS NOT NULL AND TRIM(pin_hash) != ''"
          : "pin_hash = ? AND id != ? AND pin_hash IS NOT NULL AND TRIM(pin_hash) != ''",
      whereArgs: excludeUserId == null ? [hash] : [hash, excludeUserId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<bool> setOwnerPin(String pin) async {
    final db = await database;
    final normalizedPin = _normalizePin(pin);
    if (!_isValidPin(normalizedPin)) return false;
    final ownerRows = await db.query(
      'users',
      columns: ['id'],
      where: 'role = ?',
      whereArgs: ['admin'],
      orderBy: 'created_at ASC',
      limit: 1,
    );
    if (ownerRows.isEmpty) return false;

    final ownerId = (ownerRows.first['id'] as num).toInt();
    if (await pinExists(normalizedPin, excludeUserId: ownerId)) {
      throw Exception('PIN is already used by another user');
    }

    final result = await db.update(
      'users',
      {'pin_hash': _hashPassword(normalizedPin)},
      where: 'id = ?',
      whereArgs: [ownerId],
    );
    if (result > 0) {
      await _queueUserForSync(db, ownerId);
      unawaited(syncPendingChanges());
    }
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

  Future<bool> verifyOwnerPassword(String password) async {
    final db = await database;
    final normalizedPassword = _sanitizeAuthSecret(password);
    if (!LoginInputValidator.isValidPassword(normalizedPassword)) return false;

    final result = await db.query(
      'users',
      columns: ['id'],
      where: 'role = ? AND password_hash = ?',
      whereArgs: ['admin', _hashPassword(normalizedPassword)],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<void> resetLocalBusinessData({required String ownerPassword}) async {
    if (!await verifyOwnerPassword(ownerPassword)) {
      throw Exception('Owner password is incorrect.');
    }

    await runWithCloudRestoreGuard(() async {
      final db = await database;
      await _ensureBusinessDataSchema(db);
      await db.transaction(_clearLocalBusinessRows);
      await _clearLocalProductImages();
    });
  }

  Future<void> factoryResetBusinessData({
    required String ownerPassword,
    void Function(int synced, int total, String status)? onProgress,
  }) async {
    if (!await verifyOwnerPassword(ownerPassword)) {
      throw Exception('Owner password is incorrect.');
    }

    while (_cloudRestoreInProgress || _syncInProgress) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    final db = await database;
    await _ensureBusinessDataSchema(db);
    await _ensureCloudIdentitySchema(db);
    const service = SupabaseSyncService();

    try {
      onProgress?.call(0, 0, 'Starting cloud factory reset');
      final result = await service.factoryResetCloudBusinessData();
      onProgress?.call(
        result.rowsSoftDeleted,
        result.rowsSoftDeleted,
        'Cloud factory reset complete',
      );
      await db.transaction(_clearLocalBusinessRows);
      await _clearLocalProductImages();
      return;
    } on FactoryResetFunctionUnavailable {
      onProgress?.call(
        0,
        0,
        'Factory reset service not deployed; using sync delete fallback',
      );
    }

    await db.transaction((txn) async {
      await _queueBusinessDeletesForFactoryReset(txn);
    });

    await syncPendingChanges(
      forceRetry: true,
      maxBatches: 1000,
      onProgress: onProgress,
    );
    final remaining = await pendingSyncCount();
    if (remaining > 0) {
      final lastError = await lastSyncError();
      throw Exception(
        lastError == null || lastError.trim().isEmpty
            ? 'Cloud reset could not finish. Resolve cloud sync issues and try again.'
            : 'Cloud reset could not finish: $lastError',
      );
    }

    await db.transaction(_clearLocalBusinessRows);
    await _clearLocalProductImages();
  }

  Future<void> _ensureBusinessDataSchema(Database db) async {
    await _ensureProductSchema(db);
    await _ensureSalesSchema(db);
    await _createShiftsTable(db);
    await _createShiftReadingsTable(db);
    await _createAuditLogTable(db);
    await _createSyncQueueTable(db);
  }

  Future<void> _clearLocalBusinessRows(DatabaseExecutor db) async {
    await db.delete('sync_queue');
    await db.delete('shift_readings');
    await db.delete('shifts');
    await db.delete('sales');
    await db.delete('products');
    await db.delete('audit_logs');
  }

  Future<void> _clearLocalProductImages() async {
    final imageDir = Directory(await productImagesDirectoryPath());
    if (await imageDir.exists()) {
      await imageDir.delete(recursive: true);
    }
    await imageDir.create(recursive: true);
  }

  Future<void> _queueBusinessDeletesForFactoryReset(DatabaseExecutor db) async {
    for (final tableName in const [
      'products',
      'sales',
      'shifts',
      'shift_readings',
      'audit_logs',
    ]) {
      final rows = await db.query(tableName);
      for (final row in rows) {
        final id = row['id'];
        if (id == null) continue;
        await queueSyncDelete(
          tableName,
          id,
          row,
          executor: db,
          forceCloudDelete: true,
        );
      }
    }
  }

  Future<int> createOwner({
    required String username,
    required String password,
    String? email,
    String? storeName,
    String? fullName,
  }) async {
    final db = await database;
    final normalizedUsername = _normalizeAuthUsername(username);
    final normalizedEmail = email == null
        ? null
        : _normalizeAuthUsername(email);
    final trimmedStoreName = storeName?.trim();
    final trimmedFullName = fullName?.trim();
    final row = {
      'username': normalizedUsername,
      'password_hash': _hashPassword(password),
      'full_name': trimmedFullName == null || trimmedFullName.isEmpty
          ? trimmedStoreName == null || trimmedStoreName.isEmpty
                ? normalizedUsername
                : trimmedStoreName
          : trimmedFullName,
      'email': normalizedEmail,
      'role': 'admin',
      'created_at': DateTime.now().toIso8601String(),
    };

    try {
      final existingOwner = await db.query(
        'users',
        columns: ['id'],
        where: 'role = ?',
        whereArgs: ['admin'],
        orderBy: 'created_at ASC',
        limit: 1,
      );
      if (existingOwner.isNotEmpty) {
        final ownerId = (existingOwner.first['id'] as num).toInt();
        await db.update('users', row, where: 'id = ?', whereArgs: [ownerId]);
        await _queueUserForSync(db, ownerId);
        return ownerId;
      }

      final ownerId = await db.insert('users', row);
      await _queueUserForSync(db, ownerId);
      return ownerId;
    } catch (_) {
      return -1;
    }
  }

  Future<Map<String, dynamic>?> upsertOwnerFromCloud({
    required String email,
    required String password,
    String? storeName,
    String? fullName,
  }) async {
    final db = await database;
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) return null;

    final now = DateTime.now().toIso8601String();
    final row = {
      'username': normalizedEmail,
      'password_hash': _hashPassword(password),
      'full_name': (fullName?.trim().isNotEmpty == true)
          ? fullName!.trim()
          : normalizedEmail,
      'email': normalizedEmail,
      'role': 'admin',
      'created_at': now,
    };

    final existing = await db.query(
      'users',
      columns: ['id'],
      where: 'role = ?',
      whereArgs: ['admin'],
      orderBy: 'created_at ASC',
      limit: 1,
    );

    if (existing.isEmpty) {
      final ownerId = await db.insert('users', row);
      await _queueUserForSync(db, ownerId);
      unawaited(syncPendingChanges());
      return getUserByUsername(normalizedEmail);
    }

    final ownerId = (existing.first['id'] as num).toInt();
    await db.update('users', row, where: 'id = ?', whereArgs: [ownerId]);
    await _queueUserForSync(db, ownerId);

    await recordAuditLog(
      user: normalizedEmail,
      action: 'cloud_owner_login_cached',
      details: _auditDetails({'store_name': storeName}),
    );
    unawaited(syncPendingChanges());

    return getUserByUsername(normalizedEmail);
  }

  Future<void> _queueUserForSync(DatabaseExecutor db, int userId) async {
    final rows = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    await queueSyncUpsert('users', rows.first, executor: db);
  }

  Future<Map<String, dynamic>?> resetOwnerPasswordFromCloud({
    required String email,
    required String newPassword,
  }) async {
    final db = await database;
    final normalizedEmail = _normalizeAuthUsername(email);
    final normalizedPassword = _sanitizeAuthSecret(newPassword);
    if (!LoginInputValidator.isEmail(normalizedEmail) ||
        !LoginInputValidator.isValidPassword(normalizedPassword)) {
      return null;
    }

    final ownerRows = await db.query(
      'users',
      columns: ['id'],
      where: 'role = ? AND (LOWER(email) = ? OR username = ?)',
      whereArgs: ['admin', normalizedEmail, normalizedEmail],
      orderBy: 'created_at ASC',
      limit: 1,
    );
    if (ownerRows.isEmpty) return null;

    final ownerId = (ownerRows.first['id'] as num).toInt();
    final result = await db.update(
      'users',
      {
        'username': normalizedEmail,
        'email': normalizedEmail,
        'password_hash': _hashPassword(normalizedPassword),
      },
      where: 'id = ? AND role = ?',
      whereArgs: [ownerId, 'admin'],
    );
    if (result == 0) return null;

    await _queueUserForSync(db, ownerId);
    await recordAuditLog(
      user: normalizedEmail,
      action: 'password_change',
      details: _auditDetails({
        'target_user': normalizedEmail,
        'reset': true,
        'source': 'cloud_owner_recovery',
      }),
    );
    unawaited(syncPendingChanges());
    return getUserByUsername(normalizedEmail);
  }

  /// Changes password for a given user. Returns true on success.
  Future<bool> changePassword({
    required String username,
    required String currentPassword,
    required String newPassword,
  }) async {
    final db = await database;
    final currentHash = _hashPassword(currentPassword);
    final normalizedUsername = username.trim().toLowerCase();

    // Verify current password first
    final result = await db.query(
      'users',
      where: 'username = ? AND password_hash = ?',
      whereArgs: [normalizedUsername, currentHash],
    );

    if (result.isEmpty) return false; // Wrong current password

    final newHash = _hashPassword(newPassword);
    await db.update(
      'users',
      {'password_hash': newHash},
      where: 'username = ?',
      whereArgs: [normalizedUsername],
    );

    await recordAuditLog(
      user: normalizedUsername,
      action: 'password_change',
      details: _auditDetails({'target_user': normalizedUsername}),
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

  Future<String?> getSavedOwnerResetEmail() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT email
      FROM users
      WHERE email IS NOT NULL
        AND TRIM(email) != ''
        AND role IN ('owner', 'admin')
      ORDER BY
        CASE
          WHEN role = 'owner' THEN 0
          ELSE 1
        END,
        id ASC
      LIMIT 1
      ''');
    if (result.isEmpty) return null;
    final email = result.first['email']?.toString().trim().toLowerCase() ?? '';
    return LoginInputValidator.isEmail(email) ? email : null;
  }

  Future<List<ReceiptDiscountPreset>> getReceiptDiscounts({
    bool includeDisabled = false,
  }) async {
    final db = await database;
    await _createReceiptDiscountsTable(db);
    await _seedDefaultReceiptDiscounts(db);
    final rows = await db.query(
      'receipt_discounts',
      where: includeDisabled ? null : 'enabled = ?',
      whereArgs: includeDisabled ? null : [1],
      orderBy: 'sort_order ASC, name COLLATE NOCASE ASC',
    );
    return rows.map(ReceiptDiscountPreset.fromMap).toList();
  }

  Future<int> saveReceiptDiscount({
    int? id,
    required String name,
    required double percent,
    bool enabled = true,
    String? actorUsername,
  }) async {
    final db = await database;
    await _createReceiptDiscountsTable(db);
    await _seedDefaultReceiptDiscounts(db);

    final cleanName = name
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleanName.isEmpty || cleanName.length > 50) {
      throw Exception('Discount name must be 1 to 50 characters.');
    }
    if (!percent.isFinite || percent <= 0 || percent > 100) {
      throw Exception('Discount percent must be between 1 and 100.');
    }

    final now = DateTime.now().toIso8601String();
    final maxSort =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT MAX(sort_order) FROM receipt_discounts'),
        ) ??
        0;
    final row = {
      'name': cleanName,
      'percent': percent,
      'enabled': enabled ? 1 : 0,
      'updated_at': now,
    };

    int discountId;
    if (id == null) {
      discountId = await db.insert('receipt_discounts', {
        ...row,
        'sort_order': maxSort + 10,
        'created_at': now,
      });
    } else {
      final updated = await db.update(
        'receipt_discounts',
        row,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (updated == 0) throw Exception('Discount was not found.');
      discountId = id;
    }

    await recordAuditLog(
      user: actorUsername ?? 'owner',
      action: id == null ? 'discount_create' : 'discount_update',
      details: _auditDetails({
        'discount_id': discountId,
        'name': cleanName,
        'percent': percent,
        'enabled': enabled,
      }),
    );
    return discountId;
  }

  Future<void> setReceiptDiscountEnabled({
    required int id,
    required bool enabled,
    String? actorUsername,
  }) async {
    final db = await database;
    await _createReceiptDiscountsTable(db);
    final updated = await db.update(
      'receipt_discounts',
      {
        'enabled': enabled ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (updated == 0) throw Exception('Discount was not found.');
    await recordAuditLog(
      user: actorUsername ?? 'owner',
      action: 'discount_toggle',
      details: _auditDetails({'discount_id': id, 'enabled': enabled}),
    );
  }

  Future<void> deleteReceiptDiscount({
    required int id,
    String? actorUsername,
  }) async {
    final db = await database;
    await _createReceiptDiscountsTable(db);
    final deleted = await db.delete(
      'receipt_discounts',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (deleted == 0) throw Exception('Discount was not found.');
    await recordAuditLog(
      user: actorUsername ?? 'owner',
      action: 'discount_delete',
      details: _auditDetails({'discount_id': id}),
    );
  }

  // â”€â”€â”€ Product methods â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
    double? discountPercent,
    bool discountEnabled = false,
    String? actorUsername,
  }) async {
    final db = await database;
    await _ensureProductSchema(db);
    final now = DateTime.now().toIso8601String();
    final trimmedBarcode = barcode.replaceAll(RegExp(r'[^0-9]'), '').trim();
    final trimmedName = productName
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    String? trimmedCategory;
    if (category != null) {
      trimmedCategory = category
          .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }
    String? trimmedDescription;
    if (description != null) {
      trimmedDescription = description
          .replaceAll(
            RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]'),
            ' ',
          )
          .replaceAll(RegExp(r'[ \t]+'), ' ')
          .trim();
    }
    final trimmedImageUrl = imageUrl?.trim();

    if (trimmedBarcode.length < 4 ||
        trimmedBarcode.length > 18 ||
        RegExp(r'^0+$').hasMatch(trimmedBarcode)) {
      throw Exception('Invalid barcode');
    }
    if (trimmedName.isEmpty || trimmedName.length > 120) {
      throw Exception('Invalid product name');
    }
    if (trimmedCategory == null ||
        trimmedCategory.isEmpty ||
        trimmedCategory.length > 60) {
      throw Exception('Invalid category');
    }
    if (trimmedDescription != null && trimmedDescription.length > 500) {
      throw Exception('Description is too long');
    }
    if (!price.isFinite || price <= 0 || price > 9999999.99) {
      throw Exception('Invalid selling price');
    }
    if (!costPrice.isFinite || costPrice <= 0 || costPrice > 9999999.99) {
      throw Exception('Invalid cost price');
    }
    if (stockQuantity < 0 || stockQuantity > 999999999) {
      throw Exception('Invalid stock quantity');
    }
    final sanitizedDiscountPercent = discountEnabled
        ? (discountPercent ?? 0)
        : 0.0;
    if (discountEnabled &&
        (!sanitizedDiscountPercent.isFinite ||
            sanitizedDiscountPercent <= 0 ||
            sanitizedDiscountPercent >= 100)) {
      throw Exception('Invalid product discount');
    }

    if (await barcodeExists(trimmedBarcode)) {
      throw Exception('Barcode already exists');
    }

    try {
      final productId = await db.insert('products', {
        'barcode': trimmedBarcode,
        'product_name': trimmedName,
        'category': trimmedCategory,
        'description': trimmedDescription?.isEmpty == true
            ? null
            : trimmedDescription,
        'price': price,
        'discount_percent': discountEnabled ? sanitizedDiscountPercent : null,
        'discount_enabled': discountEnabled ? 1 : 0,
        'cost_price': costPrice,
        'stock_quantity': stockQuantity,
        'image_url': trimmedImageUrl?.isEmpty == true ? null : trimmedImageUrl,
        'pending_delete': 0,
        'pending_delete_at': null,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await queueSyncUpsert('products', {
        'id': productId,
        'barcode': trimmedBarcode,
        'product_name': trimmedName,
        'category': trimmedCategory,
        'description': trimmedDescription?.isEmpty == true
            ? null
            : trimmedDescription,
        'price': price,
        'discount_percent': discountEnabled ? sanitizedDiscountPercent : null,
        'discount_enabled': discountEnabled ? 1 : 0,
        'cost_price': costPrice,
        'stock_quantity': stockQuantity,
        'image_url': trimmedImageUrl?.isEmpty == true ? null : trimmedImageUrl,
        'pending_delete': 0,
        'pending_delete_at': null,
        'created_at': now,
        'updated_at': now,
      });
      await recordAuditLog(
        user: actorUsername ?? 'system',
        action: 'product_create',
        details: _auditDetails({
          'product_id': productId,
          'product_name': trimmedName,
          'barcode': trimmedBarcode,
          'stock_quantity': stockQuantity,
          'price': price,
          'discount_percent': discountEnabled ? sanitizedDiscountPercent : null,
          'discount_enabled': discountEnabled,
        }),
      );
      unawaited(syncPendingChanges());
      return productId;
    } catch (e) {
      throw Exception('Failed to add product: $e');
    }
  }

  Future<int> insertProduct(Map<String, dynamic> product) async {
    final db = await database;
    final id = await db.insert('products', product);
    await queueSyncUpsert('products', {...product, 'id': id});
    unawaited(syncPendingChanges());
    return id;
  }

  Future<List<Map<String, dynamic>>> getProducts() async {
    final db = await database;
    return await db.query('products');
  }

  Future<int> updateProduct(
    Map<String, dynamic> product, {
    String? actorUsername,
  }) async {
    final db = await database;
    final barcode = product['barcode']?.toString().trim() ?? '';
    final id = product['id'] as int;
    final oldRows = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (barcode.isNotEmpty &&
        await barcodeExists(barcode, excludeProductId: id)) {
      throw Exception('Barcode already exists');
    }

    final discountEnabled =
        product['discount_enabled'] == true ||
        product['discount_enabled'] == 1 ||
        product['discount_enabled']?.toString() == '1';
    final discountPercent =
        (product['discount_percent'] as num?)?.toDouble() ?? 0;
    if (discountEnabled &&
        (!discountPercent.isFinite ||
            discountPercent <= 0 ||
            discountPercent >= 100)) {
      throw Exception('Invalid product discount');
    }

    final result = await db.update(
      'products',
      {
        ...product,
        'barcode': barcode,
        'discount_enabled': discountEnabled ? 1 : 0,
        'discount_percent': discountEnabled ? discountPercent : null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    if (result > 0) {
      final rows = await db.query(
        'products',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        await queueSyncUpsert('products', rows.first);
      }
      final oldProduct = oldRows.isEmpty ? <String, Object?>{} : oldRows.first;
      await recordAuditLog(
        user: actorUsername ?? 'system',
        action: 'inventory_edit',
        details: _auditDetails({
          'product_id': id,
          'product_name': product['product_name'],
          'old_stock': oldProduct['stock_quantity'],
          'new_stock': product['stock_quantity'],
          'old_price': oldProduct['price'],
          'new_price': product['price'],
          'old_cost_price': oldProduct['cost_price'],
          'new_cost_price': product['cost_price'],
          'old_discount_percent': oldProduct['discount_percent'],
          'new_discount_percent': discountEnabled ? discountPercent : null,
          'discount_enabled': discountEnabled,
        }),
      );
      unawaited(syncPendingChanges());
    }

    return result;
  }

  Future<int> deleteProduct(int id, {String? actorUsername}) async {
    final db = await database;
    await _ensureProductSchema(db);
    final oldRows = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (oldRows.isEmpty) return 0;

    final pendingDeleteAt = DateTime.now().toIso8601String();
    await db.update(
      'products',
      {'pending_delete': 1, 'pending_delete_at': pendingDeleteAt},
      where: 'id = ?',
      whereArgs: [id],
    );
    final pendingRows = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final result = await db.delete(
      'products',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (result > 0) {
      final oldProduct = pendingRows.isEmpty
          ? oldRows.first
          : pendingRows.first;
      await queueSyncDelete('products', id, oldProduct);
      await recordAuditLog(
        user: actorUsername ?? 'system',
        action: 'product_delete',
        details: _auditDetails({
          'product_id': id,
          'product_name': oldProduct['product_name'],
          'barcode': oldProduct['barcode'],
          'stock_quantity': oldProduct['stock_quantity'],
        }),
      );
      unawaited(syncPendingChanges());
    }

    return result;
  }

  // â”€â”€â”€ Sales methods â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<int> insertSale(Map<String, dynamic> sale) async {
    final db = await database;
    await _ensureSalesSchema(db);

    final row = Map<String, dynamic>.from(sale);
    final createdAt =
        DateTime.tryParse(row['created_at']?.toString() ?? '') ??
        DateTime.now();
    row['created_at'] ??= createdAt.toIso8601String();
    row['completion_due_at'] ??= createdAt
        .add(saleCompletionGracePeriod)
        .toIso8601String();
    row.putIfAbsent('completed_at', () => null);
    row['receipt_number'] ??= generateReceiptNumber(createdAt);

    final id = await db.insert('sales', row);
    await queueSyncUpsert('sales', {...row, 'id': id});
    unawaited(syncPendingChanges());
    return id;
  }

  Future<int> completeDueSales() async {
    final db = await database;
    await _ensureSalesSchema(db);

    final now = DateTime.now().toIso8601String();
    final dueRows = await db.query(
      'sales',
      where: '''
        (completed_at IS NULL OR completed_at = '')
        AND (voided_at IS NULL OR voided_at = '')
        AND completion_due_at IS NOT NULL
        AND completion_due_at != ''
        AND completion_due_at <= ?
      ''',
      whereArgs: [now],
    );
    if (dueRows.isEmpty) return 0;

    final updated = await db.update(
      'sales',
      {'completed_at': now},
      where: '''
        (completed_at IS NULL OR completed_at = '')
        AND (voided_at IS NULL OR voided_at = '')
        AND completion_due_at IS NOT NULL
        AND completion_due_at != ''
        AND completion_due_at <= ?
      ''',
      whereArgs: [now],
    );
    if (updated > 0) {
      for (final row in dueRows) {
        await queueSyncUpsert('sales', {...row, 'completed_at': now});
      }
      unawaited(syncPendingChanges());
    }
    return updated;
  }

  Future<List<Map<String, dynamic>>> getSales() async {
    final db = await database;
    await _ensureSalesSchema(db);
    await completeDueSales();
    return await db.query('sales', orderBy: 'created_at DESC');
  }

  Future<bool> voidSaleTransaction({
    required int saleId,
    required String user,
    String? reason,
    bool adminApproved = false,
    bool voidWindowHeld = false,
  }) async {
    final db = await database;
    await _ensureSalesSchema(db);
    if (!voidWindowHeld) {
      await completeDueSales();
    }

    final saleRows = await db.query(
      'sales',
      where: 'id = ?',
      whereArgs: [saleId],
      limit: 1,
    );
    if (saleRows.isEmpty) return false;

    final selectedSale = saleRows.first;
    if ((selectedSale['voided_at']?.toString() ?? '').isNotEmpty) {
      throw Exception('Sale is already voided');
    }
    final selectedShiftId = (selectedSale['shift_id'] as num?)?.toInt();
    if (selectedShiftId != null) {
      final selectedShift = await _shiftById(db, selectedShiftId);
      if (selectedShift?['status']?.toString() == 'closed') {
        throw Exception(
          'This receipt belongs to a closed shift and cannot be voided.',
        );
      }
    }
    final isCompleted =
        (selectedSale['completed_at']?.toString() ?? '').isNotEmpty;
    if (isCompleted && !adminApproved && !voidWindowHeld) {
      throw Exception('Admin PIN is required to void completed sales');
    }

    final createdAt = DateTime.tryParse(selectedSale['created_at'].toString());
    if (createdAt == null) {
      throw Exception('Sale timestamp is invalid');
    }

    final start = createdAt.subtract(const Duration(seconds: 1));
    final end = createdAt.add(const Duration(seconds: 1));
    final now = DateTime.now().toIso8601String();
    final sanitizedUser = _sanitizeAuditText(user, maxLength: 80);
    final normalizedUser = sanitizedUser.isEmpty ? 'unknown' : sanitizedUser;
    final trimmedReason = reason == null
        ? null
        : _sanitizeAuditText(reason, maxLength: 250, multiline: true);

    late List<Map<String, Object?>> saleItems;
    await db.transaction((txn) async {
      saleItems = await txn.query(
        'sales',
        where:
            'created_at >= ? AND created_at <= ? AND (voided_at IS NULL OR voided_at = ?)',
        whereArgs: [start.toIso8601String(), end.toIso8601String(), ''],
        orderBy: 'id ASC',
      );

      if (saleItems.isEmpty) {
        throw Exception('Sale is already voided');
      }

      for (final item in saleItems) {
        final productId = (item['product_id'] as num?)?.toInt();
        final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
        if (productId == null || quantity <= 0) continue;

        await txn.rawUpdate(
          '''
          UPDATE products
          SET stock_quantity = stock_quantity + ?,
              updated_at = ?
          WHERE id = ?
          ''',
          [quantity, now, productId],
        );
      }

      await txn.update(
        'sales',
        {
          'voided_at': now,
          'voided_by': normalizedUser,
          'void_reason': trimmedReason == null || trimmedReason.isEmpty
              ? null
              : trimmedReason,
        },
        where: 'id IN (${List.filled(saleItems.length, '?').join(',')})',
        whereArgs: saleItems.map((item) => item['id']).toList(),
      );

      for (final item in saleItems) {
        final productId = (item['product_id'] as num?)?.toInt();
        if (productId != null) {
          final rows = await txn.query(
            'products',
            where: 'id = ?',
            whereArgs: [productId],
            limit: 1,
          );
          if (rows.isNotEmpty) {
            await queueSyncUpsert('products', rows.first, executor: txn);
          }
        }
        await queueSyncUpsert('sales', {
          ...item,
          'voided_at': now,
          'voided_by': normalizedUser,
          'void_reason': trimmedReason == null || trimmedReason.isEmpty
              ? null
              : trimmedReason,
        }, executor: txn);
      }
    });

    final total = saleItems.fold<double>(
      0,
      (sum, item) => sum + ((item['total'] as num?)?.toDouble() ?? 0),
    );
    final quantity = saleItems.fold<int>(
      0,
      (sum, item) => sum + ((item['quantity'] as num?)?.toInt() ?? 0),
    );

    await recordVoidSaleAudit(
      user: normalizedUser,
      saleId: saleId,
      details: _auditDetails({
        'sale_ids': saleItems.map((item) => item['id']).toList(),
        'items': saleItems.length,
        'quantity': quantity,
        'total': total,
        'reason': trimmedReason,
        'completed': isCompleted,
        'admin_approved': adminApproved,
        'void_window_held': voidWindowHeld,
      }),
    );

    unawaited(syncPendingChanges());
    return true;
  }

  // â”€â”€â”€ Staff management methods â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Creates a new staff user. Returns the user id if successful, -1 otherwise.
  Future<int> createStaff({
    required String fullName,
    required String pin,
  }) async {
    final db = await database;
    final normalizedPin = _normalizePin(pin);
    if (!_isValidPin(normalizedPin)) return -1;
    if (await pinExists(normalizedPin)) return -2;

    final now = DateTime.now();
    final generatedUsername =
        'staff_${now.microsecondsSinceEpoch}_${fullName.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '')}';
    try {
      return await db.insert('users', {
        'username': generatedUsername,
        'password_hash': _hashPassword(normalizedPin),
        'pin_hash': _hashPassword(normalizedPin),
        'full_name': fullName.trim(),
        'email': null,
        'role': 'staff',
        'created_at': now.toIso8601String(),
      });
    } catch (e) {
      return -1;
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
    final oldRows = await db.query(
      'users',
      where: 'id = ? AND role = ?',
      whereArgs: [userId, 'staff'],
      limit: 1,
    );
    final result = await db.delete(
      'users',
      where: 'id = ? AND role = ?',
      whereArgs: [userId, 'staff'],
    );
    if (result > 0) {
      final oldUser = oldRows.isEmpty ? <String, Object?>{} : oldRows.first;
      await queueSyncDelete('users', userId, oldUser);
      unawaited(syncPendingChanges());
    }
    return result > 0;
  }

  /// Updates staff member info.
  Future<bool> updateStaff({
    required int userId,
    required String fullName,
  }) async {
    final db = await database;
    final result = await db.update(
      'users',
      {'full_name': fullName.trim()},
      where: 'id = ? AND role = ?',
      whereArgs: [userId, 'staff'],
    );
    return result > 0;
  }

  /// Resets a staff member's password.
  Future<bool> resetStaffPassword({
    required int userId,
    required String newPassword,
    String? actorUsername,
  }) async {
    final db = await database;
    final result = await db.update(
      'users',
      {'password_hash': _hashPassword(newPassword)},
      where: 'id = ?',
      whereArgs: [userId],
    );
    if (result > 0) {
      await recordAuditLog(
        user: actorUsername ?? 'system',
        action: 'password_change',
        details: _auditDetails({'target_user_id': userId, 'reset': true}),
      );
    }
    return result > 0;
  }

  Future<bool> resetStaffPin({
    required int userId,
    required String pin,
    String? actorUsername,
  }) async {
    final db = await database;
    final normalizedPin = _normalizePin(pin);
    if (!_isValidPin(normalizedPin)) return false;
    if (await pinExists(normalizedPin, excludeUserId: userId)) {
      throw Exception('PIN is already used by another user');
    }

    final hash = _hashPassword(normalizedPin);
    final result = await db.update(
      'users',
      {'pin_hash': hash, 'password_hash': hash},
      where: 'id = ? AND role = ?',
      whereArgs: [userId, 'staff'],
    );
    if (result > 0) {
      await recordAuditLog(
        user: actorUsername ?? 'system',
        action: 'pin_change',
        details: _auditDetails({'target_user_id': userId, 'reset': true}),
      );
    }
    return result > 0;
  }

  Future<bool> barcodeExists(String barcode, {int? excludeProductId}) async {
    final db = await database;
    final trimmedBarcode = barcode.trim();
    if (trimmedBarcode.isEmpty) return false;

    final result = await db.query(
      'products',
      where: excludeProductId == null
          ? 'barcode = ? COLLATE NOCASE'
          : 'barcode = ? COLLATE NOCASE AND id != ?',
      whereArgs: excludeProductId == null
          ? [trimmedBarcode]
          : [trimmedBarcode, excludeProductId],
      limit: 1,
    );
    return result.isNotEmpty;
  }
}
