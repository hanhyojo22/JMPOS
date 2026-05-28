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
  static const int _dbVersion = 9;
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
        await _createSyncQueueTable(db);
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
        barcode TEXT NOT NULL,
        product_name TEXT NOT NULL,
        category TEXT,
        description TEXT,
        price REAL NOT NULL,
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
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        price REAL NOT NULL,
        total REAL NOT NULL,
        image_url TEXT,
        voided_at TEXT,
        voided_by TEXT,
        void_reason TEXT,
        completion_due_at TEXT,
        completed_at TEXT,
        receipt_number TEXT,
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

    await _createAuditLogTable(db);
    await _createSyncQueueTable(db);

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
  }

  Future<void> _createAuditLogTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS audit_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
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
        operation TEXT NOT NULL,
        payload TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        next_retry_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        synced_at TEXT
      )
    ''');
    await _ensureSyncQueueSchema(db);
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
    await _queueSyncEvent(
      db,
      tableName: tableName,
      localId: localId,
      operation: 'upsert',
      payload: row,
    );
  }

  Future<void> queueSyncDelete(
    String tableName,
    Object localId,
    Map<String, Object?> oldRow, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await database;
    await _createSyncQueueTable(db);
    await _queueSyncEvent(
      db,
      tableName: tableName,
      localId: localId.toString(),
      operation: 'delete',
      payload: oldRow,
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
    final queueKey = '$tableName:$localId';
    await db.insert('sync_queue', {
      'queue_key': queueKey,
      'table_name': tableName,
      'local_id': localId,
      'operation': operation,
      'payload': jsonEncode(payload),
      'status': 'pending',
      'attempts': 0,
      'last_error': null,
      'next_retry_at': null,
      'created_at': now,
      'updated_at': now,
      'synced_at': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> syncPendingChanges({
    int limit = 100,
    int maxBatches = 100,
    void Function(int synced, int total, String status)? onProgress,
  }) async {
    if (_syncInProgress) return 0;
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
          where: '''
            status != ?
            AND (next_retry_at IS NULL OR next_retry_at = '' OR next_retry_at <= ?)
          ''',
          whereArgs: ['synced', now],
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
          await service.uploadEvents(pending.cast<Map<String, Object?>>());
          final syncedAt = DateTime.now().toIso8601String();
          final ids = pending.map((row) => row['id']).toList();
          await db.update(
            'sync_queue',
            {
              'status': 'synced',
              'synced_at': syncedAt,
              'updated_at': syncedAt,
              'last_error': null,
              'next_retry_at': null,
            },
            where: 'id IN (${List.filled(ids.length, '?').join(',')})',
            whereArgs: ids,
          );
          syncedTotal += pending.length;
          onProgress?.call(
            syncedTotal,
            total,
            'Uploaded $syncedTotal of $total',
          );
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
            ''',
            [
              'failed',
              message,
              failedAt.toIso8601String(),
              retryAt.toIso8601String(),
              ...ids,
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
    await _ensureProductSchema(db);
    await _ensureSalesSchema(db);
    await _createAuditLogTable(db);
    await _createSyncQueueTable(db);

    final products = await db.query('products');
    for (final row in products) {
      await _queueSnapshotUpsert(db, 'products', row);
    }

    final sales = await db.query('sales');
    for (final row in sales) {
      await _queueSnapshotUpsert(db, 'sales', row);
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

  Future<int> pullCloudSnapshotToLocal({
    void Function(int imported, int total, String status)? onProgress,
  }) async {
    final db = await database;
    await _ensureProductSchema(db);
    await _ensureSalesSchema(db);
    await _createAuditLogTable(db);
    await _createSyncQueueTable(db);

    const service = SupabaseSyncService();
    onProgress?.call(0, 0, 'Downloading cloud data');
    final snapshot = await service.downloadStoreSnapshot();
    final imageDirPath = await productImagesDirectoryPath();
    await Directory(imageDirPath).create(recursive: true);

    final total = snapshot.values.fold<int>(
      0,
      (sum, rows) => sum + rows.length,
    );
    var imported = 0;

    await db.transaction((txn) async {
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
        'audit_logs',
        snapshot['audit_logs'] ?? const [],
        _cloudAuditLogToLocalRow,
      );
      onProgress?.call(imported, total, 'Restored audit log');
    });

    await _markCloudSnapshotSynced(snapshot);
    onProgress?.call(imported, total, 'Cloud data restored');
    return imported;
  }

  Future<int> _importCloudRows(
    DatabaseExecutor db,
    String tableName,
    List<Map<String, dynamic>> cloudRows,
    FutureOr<Map<String, Object?>> Function(Map<String, dynamic>) mapper,
  ) async {
    var imported = 0;
    for (final cloudRow in cloudRows) {
      final row = await mapper(cloudRow);
      final id = row['id'];
      if (id == null) continue;
      await db.insert(
        tableName,
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      imported += 1;
    }
    return imported;
  }

  Future<void> _markCloudSnapshotSynced(
    Map<String, List<Map<String, dynamic>>> snapshot,
  ) async {
    final db = await database;
    await _createSyncQueueTable(db);
    final syncedAt = DateTime.now().toIso8601String();

    for (final entry in snapshot.entries) {
      for (final cloudRow in entry.value) {
        final localId = cloudRow['local_id']?.toString();
        if (localId == null || localId.isEmpty) continue;
        await db.insert('sync_queue', {
          'queue_key': '${entry.key}:$localId',
          'table_name': entry.key,
          'local_id': localId,
          'operation': cloudRow['operation']?.toString() ?? 'upsert',
          'payload': jsonEncode(_cloudPayloadMap(cloudRow)),
          'status': 'synced',
          'attempts': 0,
          'last_error': null,
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
      'id': _cloudLocalId(cloudRow),
      'barcode': _cloudString(payload, cloudRow, 'barcode'),
      'product_name': _cloudString(payload, cloudRow, 'product_name'),
      'category': _cloudNullableString(payload, cloudRow, 'category'),
      'description': _cloudNullableString(payload, cloudRow, 'description'),
      'price': _cloudNumber(payload, cloudRow, 'price'),
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
      'id': _cloudLocalId(cloudRow),
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
      'id': _cloudLocalId(cloudRow),
      'product_id': _cloudInt(payload, cloudRow, 'local_product_id'),
      'product_name': _cloudString(payload, cloudRow, 'product_name'),
      'quantity': _cloudInt(payload, cloudRow, 'quantity'),
      'price': _cloudNumber(payload, cloudRow, 'price'),
      'total': _cloudNumber(payload, cloudRow, 'total'),
      'image_url': null,
      'voided_at': _cloudNullableString(payload, cloudRow, 'voided_at'),
      'voided_by': _cloudNullableString(payload, cloudRow, 'voided_by'),
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
      'created_at':
          _cloudNullableString(payload, cloudRow, 'created_at') ??
          DateTime.now().toIso8601String(),
    };
  }

  Map<String, Object?> _cloudAuditLogToLocalRow(Map<String, dynamic> cloudRow) {
    final payload = _cloudPayloadMap(cloudRow);
    return {
      'id': _cloudLocalId(cloudRow),
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

  int? _cloudLocalId(Map<String, dynamic> cloudRow) {
    return int.tryParse(cloudRow['local_id']?.toString() ?? '');
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

  int _cloudInt(
    Map<String, Object?> payload,
    Map<String, dynamic> cloudRow,
    String key,
  ) {
    final value = payload.containsKey(key) ? payload[key] : cloudRow[key];
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
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

    final queueKey = '$tableName:$localId';
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
      payload: row,
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

  // ─── Password hashing ────────────────────────────────────────────────────────
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

  // ─── Auth methods ─────────────────────────────────────────────────────────────

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
    if (normalizedPin.length < 4 || normalizedPin.length > 6) return null;
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
    if (normalizedPin.length < 4 || normalizedPin.length > 6) return null;

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
    final hash = _hashPassword(pin);
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
    if (await pinExists(pin, excludeUserId: ownerId)) {
      throw Exception('PIN is already used by another user');
    }

    final result = await db.update(
      'users',
      {'pin_hash': _hashPassword(pin)},
      where: 'id = ?',
      whereArgs: [ownerId],
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
        return ownerId;
      }

      return await db.insert('users', row);
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
      await db.insert('users', row);
      return getUserByUsername(normalizedEmail);
    }

    final ownerId = (existing.first['id'] as num).toInt();
    await db.update('users', row, where: 'id = ?', whereArgs: [ownerId]);

    await recordAuditLog(
      user: normalizedEmail,
      action: 'cloud_owner_login_cached',
      details: _auditDetails({'store_name': storeName}),
    );

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

    final result = await db.update(
      'products',
      {...product, 'barcode': barcode},
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

  // ─── Sales methods ────────────────────────────────────────────────────────────

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

  // ─── Staff management methods ──────────────────────────────────────────────────

  /// Creates a new staff user. Returns the user id if successful, -1 otherwise.
  Future<int> createStaff({
    required String fullName,
    required String pin,
  }) async {
    final db = await database;
    if (await pinExists(pin)) return -2;

    final now = DateTime.now();
    final generatedUsername =
        'staff_${now.microsecondsSinceEpoch}_${fullName.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '')}';
    try {
      return await db.insert('users', {
        'username': generatedUsername,
        'password_hash': _hashPassword(pin),
        'pin_hash': _hashPassword(pin),
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
    if (await pinExists(pin, excludeUserId: userId)) {
      throw Exception('PIN is already used by another user');
    }

    final hash = _hashPassword(pin);
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
