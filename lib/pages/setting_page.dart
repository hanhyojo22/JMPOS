import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_saver/file_saver.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pos_app/database/database_helper.dart';
import 'package:pos_app/main.dart';
import 'package:pos_app/services/env_config.dart';
import 'package:pos_app/services/supabase_backup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

// ─── Settings Page ────────────────────────────────────────────────────────────
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.barcodeScannerEnabled,
    required this.onBarcodeScannerChanged,
    required this.currentUsername,
  });

  final bool barcodeScannerEnabled;
  final ValueChanged<bool> onBarcodeScannerChanged;
  final String currentUsername;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _lastBackupKey = 'last_database_backup_at';
  static const _lastOnlineBackupKey = 'last_online_database_backup_at';
  static const _lastSalesExportKey = 'last_sales_export_at';
  static const _storeNameKey = 'store_name';

  // ── Design tokens ────────────────────────────────────────s──────────────────
  static const Color _primary = Color(0xFF5C6BC0);
  static const Color _surface = Color(0xFFF4F5FF);
  static const Color _border = Color(0xFFEEEEEE);
  static const Color _textPrimary = Color(0xFF1A1F36);
  static const Color _textSecondary = Color(0xFF6B7280);
  static const Color _textTertiary = Color(0xFFAAAAAA);
  static const Color _danger = Color(0xFFDC2626);
  static const Color _dangerBg = Color(0xFFFEE2E2);

  // ── Preferences state ──────────────────────────────────────────────────────
  bool _notifications = true;
  bool _darkMode = false;
  late bool _barcodeScanner;
  bool _keepScreenOn = false;
  bool _loadedThemeValue = false;
  bool _isBackingUp = false;
  bool _isOnlineBackingUp = false;
  bool _isSyncingCloud = false;
  bool _isRestoring = false;
  bool _isExportingSales = false;
  DateTime? _lastBackupAt;
  DateTime? _lastOnlineBackupAt;
  DateTime? _lastSalesExportAt;
  int _pendingSyncCount = 0;
  int _cloudSyncDone = 0;
  int _cloudSyncTotal = 0;
  int _cloudSyncStep = 0;
  String _cloudSyncStatus = '';
  String _storeName = 'My Sari-Sari Store';
  bool _pinEnabled = false;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _pageSurface => _isDark ? const Color(0xFF0F172A) : _surface;
  Color get _cardSurface => _isDark ? const Color(0xFF111827) : Colors.white;
  Color get _dividerColor => _isDark ? const Color(0xFF253047) : _border;
  Color get _primaryText => _isDark ? const Color(0xFFF8FAFC) : _textPrimary;
  Color get _secondaryText =>
      _isDark ? const Color(0xFFCBD5E1) : _textSecondary;
  Color get _tertiaryText => _isDark ? const Color(0xFF94A3B8) : _textTertiary;

  @override
  void initState() {
    super.initState();
    _barcodeScanner = widget.barcodeScannerEnabled;
    _loadStoreName();
    _loadPinState();
    _loadLastBackupDate();
    _loadLastOnlineBackupDate();
    _loadLastSalesExportDate();
    _loadPendingSyncCount();
  }

  Future<void> _loadStoreName() async {
    final prefs = await SharedPreferences.getInstance();
    final storeName = prefs.getString(_storeNameKey)?.trim();
    if (!mounted || storeName == null || storeName.isEmpty) return;
    setState(() => _storeName = storeName);
  }

  Future<void> _loadPinState() async {
    final enabled = await DatabaseHelper.instance.ownerPinExists();
    if (!mounted) return;
    setState(() => _pinEnabled = enabled);
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.barcodeScannerEnabled != widget.barcodeScannerEnabled) {
      _barcodeScanner = widget.barcodeScannerEnabled;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadedThemeValue) return;
    _darkMode =
        MyApp.of(context)?.isDarkMode ??
        Theme.of(context).brightness == Brightness.dark;
    _loadedThemeValue = true;
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageSurface,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  _buildSection(
                    label: 'Store',
                    children: [
                      _SettingsRow(
                        icon: Icons.storefront_outlined,
                        iconBg: const Color(0xFFEEEDFE),
                        iconColor: const Color(0xFF534AB7),
                        label: 'Store name',
                        subtitle: _storeName,
                        onTap: () {},
                      ),
                      _SettingsRow(
                        icon: Icons.monetization_on_outlined,
                        iconBg: const Color(0xFFE1F5EE),
                        iconColor: const Color(0xFF0F6E56),
                        label: 'Currency',
                        subtitle: 'Philippine Peso (₱)',
                        onTap: () {},
                      ),
                      _SettingsRow(
                        icon: Icons.receipt_long_outlined,
                        iconBg: const Color(0xFFFAEEDA),
                        iconColor: const Color(0xFF854F0B),
                        label: 'Receipt footer',
                        subtitle: 'Thank you for shopping!',
                        onTap: () {},
                        isLast: true,
                      ),
                    ],
                  ),
                  _buildSection(
                    label: 'Preferences',
                    children: [
                      _SettingsRow(
                        icon: Icons.notifications_outlined,
                        iconBg: const Color(0xFFEEEDFE),
                        iconColor: const Color(0xFF534AB7),
                        label: 'Notifications',
                        trailing: _buildToggle(_notifications, (v) {
                          HapticFeedback.lightImpact();
                          setState(() => _notifications = v);
                        }),
                      ),
                      _SettingsRow(
                        icon: Icons.dark_mode_outlined,
                        iconBg: const Color(0xFFF1EFE8),
                        iconColor: const Color(0xFF5F5E5A),
                        label: 'Dark mode',
                        trailing: _buildToggle(_darkMode, (v) {
                          HapticFeedback.lightImpact();
                          setState(() => _darkMode = v);

                          MyApp.of(context)?.toggleTheme(v);
                        }),
                      ),
                      _SettingsRow(
                        icon: Icons.barcode_reader,
                        iconBg: const Color(0xFFE1F5EE),
                        iconColor: const Color(0xFF0F6E56),
                        label: 'Barcode scanner',
                        trailing: _buildToggle(_barcodeScanner, (v) {
                          HapticFeedback.lightImpact();
                          setState(() => _barcodeScanner = v);
                          widget.onBarcodeScannerChanged(v);
                        }),
                      ),
                      _SettingsRow(
                        icon: Icons.pin_outlined,
                        iconBg: const Color(0xFFE6F1FB),
                        iconColor: const Color(0xFF185FA5),
                        label: 'PIN login',
                        subtitle: _pinEnabled
                            ? '4-digit PIN is enabled'
                            : 'Set a 4-digit PIN',
                        onTap: _showPinDialog,
                      ),
                      _SettingsRow(
                        icon: Icons.tablet_outlined,
                        iconBg: const Color(0xFFFAEEDA),
                        iconColor: const Color(0xFF854F0B),
                        label: 'Keep screen on',
                        trailing: _buildToggle(_keepScreenOn, (v) {
                          HapticFeedback.lightImpact();
                          setState(() => _keepScreenOn = v);
                        }),
                        isLast: true,
                      ),
                    ],
                  ),
                  _buildSection(
                    label: 'Data',
                    children: [
                      _SettingsRow(
                        icon: Icons.upload_file_outlined,
                        iconBg: const Color(0xFFE6F1FB),
                        iconColor: const Color(0xFF185FA5),
                        label: 'Export sales report',
                        subtitle: _lastSalesExportSubtitle,
                        trailing: _isExportingSales
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : null,
                        onTap: _isExportingSales ? null : _exportSalesReport,
                      ),
                      _SettingsRow(
                        icon: Icons.backup_outlined,
                        iconBg: const Color(0xFFEAF3DE),
                        iconColor: const Color(0xFF3B6D11),
                        label: 'Backup database',
                        subtitle: _lastBackupSubtitle,
                        trailing: _isBackingUp
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : null,
                        onTap: _isBackingUp ? null : _backupDatabase,
                      ),
                      _SettingsRow(
                        icon: Icons.cloud_sync_outlined,
                        iconBg: const Color(0xFFEAF3FF),
                        iconColor: const Color(0xFF5B3BB3),
                        label: 'Cloud sync',
                        subtitle: _cloudSyncSubtitle,
                        trailing: _isSyncingCloud
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : _pendingSyncCount > 0
                            ? _buildBadge(
                                '$_pendingSyncCount',
                                const Color(0xFFFFF4DE),
                                const Color(0xFF9A5B00),
                              )
                            : _buildBadge(
                                'Synced',
                                const Color(0xFFE1F5EE),
                                const Color(0xFF0F6E56),
                              ),
                        onTap: _isSyncingCloud ? null : _syncCloudNow,
                      ),
                      if (_isSyncingCloud)
                        _CloudSyncProgressRow(
                          done: _cloudSyncDone,
                          total: _cloudSyncTotal,
                          step: _cloudSyncStep,
                        ),
                      _SettingsRow(
                        icon: Icons.cloud_upload_outlined,
                        iconBg: const Color(0xFFE8F0FE),
                        iconColor: const Color(0xFF315BB8),
                        label: 'Online backup',
                        subtitle: _lastOnlineBackupSubtitle,
                        trailing: _isOnlineBackingUp
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : null,
                        onTap: _isOnlineBackingUp
                            ? null
                            : _backupDatabaseOnline,
                      ),
                      _SettingsRow(
                        icon: Icons.restore_outlined,
                        iconBg: const Color(0xFFFFF4DE),
                        iconColor: const Color(0xFF9A5B00),
                        label: 'Restore database',
                        subtitle: 'Import a saved backup file',
                        trailing: _isRestoring
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : null,
                        onTap: _isRestoring ? null : _restoreDatabase,
                      ),
                      _SettingsRow(
                        icon: Icons.delete_outline_rounded,
                        iconBg: const Color(0xFFFCEBEB),
                        iconColor: const Color(0xFFA32D2D),
                        label: 'Clear all data',
                        subtitle: 'Irreversible — proceed with care',
                        trailing: _buildBadge('Danger', _dangerBg, _danger),
                        onTap: () => _showClearDataDialog(),
                        isLast: true,
                      ),
                    ],
                  ),
                  _buildSection(
                    label: 'About',
                    children: [
                      _SettingsRow(
                        icon: Icons.info_outline_rounded,
                        iconBg: const Color(0xFFF1EFE8),
                        iconColor: const Color(0xFF5F5E5A),
                        label: 'App version',
                        trailing: Text(
                          'v1.4.2',
                          style: TextStyle(fontSize: 13, color: _secondaryText),
                        ),
                      ),
                      _SettingsRow(
                        icon: Icons.shield_outlined,
                        iconBg: const Color(0xFFF1EFE8),
                        iconColor: const Color(0xFF5F5E5A),
                        label: 'Privacy policy',
                        trailing: Icon(
                          Icons.open_in_new_rounded,
                          size: 16,
                          color: _tertiaryText,
                        ),
                        onTap: () {},
                      ),
                      _SettingsRow(
                        icon: Icons.help_outline_rounded,
                        iconBg: const Color(0xFFF1EFE8),
                        iconColor: const Color(0xFF5F5E5A),
                        label: 'Help & support',
                        onTap: () {},
                        isLast: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── App bar ────────────────────────────────────────────────────────────────
  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Text(
            'Settings',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: _primaryText,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );
  }

  // ── Profile card ───────────────────────────────────────────────────────────

  // ── Section wrapper ────────────────────────────────────────────────────────
  Widget _buildSection({String? label, required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _tertiaryText,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
          Container(
            decoration: BoxDecoration(
              color: _cardSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _dividerColor, width: 0.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  // ── Logout row ─────────────────────────────────────────────────────────────

  // ── Helpers ────────────────────────────────────────────────────────────────
  Widget _buildToggle(bool value, ValueChanged<bool>? onChanged) {
    return Switch.adaptive(
      value: value,
      onChanged: onChanged,
      activeThumbColor: _primary, // replaces activeColor
      activeTrackColor: _primary.withValues(alpha: 0.5), // optional for track
      inactiveThumbColor: _isDark ? const Color(0xFFCBD5E1) : null,
      inactiveTrackColor: _isDark ? const Color(0xFF334155) : null,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildBadge(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  String get _lastBackupSubtitle {
    final lastBackupAt = _lastBackupAt;
    if (lastBackupAt == null) return 'No backup yet';
    return 'Last backup: ${_formatBackupDate(lastBackupAt)}';
  }

  String get _lastOnlineBackupSubtitle {
    final lastBackupAt = _lastOnlineBackupAt;
    if (lastBackupAt == null) return 'Upload to Supabase Storage';
    return 'Last upload: ${_formatBackupDate(lastBackupAt)}';
  }

  String get _cloudSyncSubtitle {
    if (_isSyncingCloud) {
      if (_cloudSyncStatus.isNotEmpty) return _cloudSyncStatus;
      if (_cloudSyncTotal <= 0) return 'Preparing local changes';
      return 'Uploading $_cloudSyncDone of $_cloudSyncTotal changes';
    }
    if (_pendingSyncCount == 0) return 'SQLite is synced to Supabase';
    return '$_pendingSyncCount local change${_pendingSyncCount == 1 ? '' : 's'} waiting';
  }

  String get _lastSalesExportSubtitle {
    final lastSalesExportAt = _lastSalesExportAt;
    if (lastSalesExportAt == null) return 'CSV export';
    return 'Last export: ${_formatBackupDate(lastSalesExportAt)}';
  }

  Future<void> _loadLastBackupDate() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_lastBackupKey);
    final parsed = value == null ? null : DateTime.tryParse(value);

    if (!mounted) return;
    setState(() => _lastBackupAt = parsed);
  }

  Future<void> _saveLastBackupDate(DateTime value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastBackupKey, value.toIso8601String());

    if (!mounted) return;
    setState(() => _lastBackupAt = value);
  }

  Future<void> _loadLastOnlineBackupDate() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_lastOnlineBackupKey);
    final parsed = value == null ? null : DateTime.tryParse(value);

    if (!mounted) return;
    setState(() => _lastOnlineBackupAt = parsed);
  }

  Future<void> _saveLastOnlineBackupDate(DateTime value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastOnlineBackupKey, value.toIso8601String());

    if (!mounted) return;
    setState(() => _lastOnlineBackupAt = value);
  }

  Future<void> _loadPendingSyncCount() async {
    final count = await DatabaseHelper.instance.pendingSyncCount();
    if (!mounted) return;
    setState(() => _pendingSyncCount = count);
  }

  Future<void> _syncCloudNow() async {
    HapticFeedback.lightImpact();
    setState(() {
      _isSyncingCloud = true;
      _cloudSyncDone = 0;
      _cloudSyncTotal = _pendingSyncCount;
      _cloudSyncStep = 0;
      _cloudSyncStatus = 'Preparing local changes';
    });
    await WakelockPlus.enable();

    try {
      await DatabaseHelper.instance.queueLocalSnapshotForSync();
      final total = await DatabaseHelper.instance.pendingSyncCount();
      if (mounted) {
        setState(() {
          _cloudSyncDone = 0;
          _cloudSyncTotal = total;
          _cloudSyncStep = 0;
          _pendingSyncCount = total;
          _cloudSyncStatus = total == 0
              ? 'SQLite is synced to Supabase'
              : 'Uploading 0 of $total changes';
        });
      }
      final synced = await DatabaseHelper.instance.syncPendingChanges(
        onProgress: (done, total, status) {
          if (!mounted) return;
          setState(() {
            _cloudSyncDone = done;
            _cloudSyncTotal = total;
            if (total > 0) _cloudSyncStep += 1;
            _pendingSyncCount = total - done;
            _cloudSyncStatus = status;
          });
        },
      );
      final pending = await DatabaseHelper.instance.pendingSyncCount();
      final lastError = await DatabaseHelper.instance.lastSyncError();
      if (!mounted) return;
      setState(() => _pendingSyncCount = pending);

      final errorText =
          lastError == null || lastError.trim().isEmpty
          ? ''
          : ' Error: ${lastError.trim()}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pending == 0
                ? 'Cloud sync complete. Uploaded $synced change${synced == 1 ? '' : 's'}.'
                : 'Cloud sync paused. $pending change${pending == 1 ? '' : 's'} still waiting.$errorText',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: pending == 0 ? const Color(0xFF0F6E56) : _danger,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await _loadPendingSyncCount();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cloud sync failed: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _danger,
        ),
      );
    } finally {
      await WakelockPlus.disable();
      if (mounted) {
        setState(() {
          _isSyncingCloud = false;
          _cloudSyncDone = 0;
          _cloudSyncTotal = 0;
          _cloudSyncStep = 0;
          _cloudSyncStatus = '';
        });
      }
    }
  }

  Future<void> _loadLastSalesExportDate() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_lastSalesExportKey);
    final parsed = value == null ? null : DateTime.tryParse(value);

    if (!mounted) return;
    setState(() => _lastSalesExportAt = parsed);
  }

  Future<void> _saveLastSalesExportDate(DateTime value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSalesExportKey, value.toIso8601String());

    if (!mounted) return;
    setState(() => _lastSalesExportAt = value);
  }

  Future<void> _showPinDialog() async {
    HapticFeedback.lightImpact();
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const _PinSetupDialog(),
    );

    if (!mounted || saved != true) return;
    await _loadPinState();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('PIN login updated'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatBackupDate(DateTime value) {
    final local = value.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = local.hour == 0
        ? 12
        : local.hour > 12
        ? local.hour - 12
        : local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '${months[local.month - 1]} ${local.day}, ${local.year} $hour:$minute $period';
  }

  Future<void> _exportSalesReport() async {
    HapticFeedback.lightImpact();
    setState(() => _isExportingSales = true);

    try {
      final sales = await DatabaseHelper.instance.getSales();
      if (!mounted) return;

      if (sales.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No sales to export yet'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final csv = _buildSalesCsv(sales);
      final timestamp = DateTime.now().toIso8601String().replaceAll(
        RegExp(r'[:.]'),
        '-',
      );
      final savedPath = await FileSaver.instance.saveAs(
        name: 'sales_report_$timestamp',
        bytes: Uint8List.fromList(utf8.encode(csv)),
        fileExtension: 'csv',
        mimeType: MimeType.other,
        customMimeType: 'text/csv',
      );

      if (!mounted) return;
      await _saveLastSalesExportDate(DateTime.now());
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Sales report exported',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: SelectableText(
            savedPath ?? 'Sales report CSV was saved.',
            style: TextStyle(color: _secondaryText),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isExportingSales = false);
      }
    }
  }

  String _buildSalesCsv(List<Map<String, dynamic>> sales) {
    final buffer = StringBuffer();
    buffer.writeln(
      'Sale ID,Date,Product ID,Product Name,Quantity,Unit Price,Total,Status,Voided By,Void Reason,Image',
    );

    for (final sale in sales) {
      final isVoided = (sale['voided_at']?.toString() ?? '').isNotEmpty;
      buffer.writeln(
        [
          sale['id'],
          sale['created_at'],
          sale['product_id'],
          sale['product_name'],
          sale['quantity'],
          sale['price'],
          sale['total'],
          isVoided ? 'Voided' : 'Completed',
          sale['voided_by'],
          sale['void_reason'],
          sale['image_url'],
        ].map(_csvCell).join(','),
      );
    }

    return buffer.toString();
  }

  String _csvCell(Object? value) {
    final text = (value ?? '').toString();
    final escaped = text.replaceAll('"', '""');
    if (escaped.contains(',') ||
        escaped.contains('"') ||
        escaped.contains('\n') ||
        escaped.contains('\r')) {
      return '"$escaped"';
    }
    return escaped;
  }

  Future<void> _backupDatabase() async {
    HapticFeedback.lightImpact();
    setState(() => _isBackingUp = true);

    try {
      final databasePath = await DatabaseHelper.instance.createBackupArchive();
      final timestamp = DateTime.now().toIso8601String().replaceAll(
        RegExp(r'[:.]'),
        '-',
      );
      final savedPath = await FileSaver.instance.saveAs(
        name: 'pos_backup_$timestamp',
        filePath: databasePath,
        fileExtension: 'posbackup',
        mimeType: MimeType.other,
        customMimeType: 'application/zip',
      );
      if (!mounted) return;
      await _saveLastBackupDate(DateTime.now());
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Backup created',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: SelectableText(
            savedPath ?? 'Database backup was saved.',
            style: TextStyle(color: _secondaryText),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup failed: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isBackingUp = false);
      }
    }
  }

  SupabaseBackupConfig get _supabaseBackupConfig => SupabaseBackupConfig(
    projectUrl: EnvConfig.supabaseUrl,
    anonKey: EnvConfig.supabaseAnonKey,
    bucket: EnvConfig.supabaseBackupBucket,
  );

  Future<void> _backupDatabaseOnline() async {
    HapticFeedback.lightImpact();

    final config = _supabaseBackupConfig;
    if (!config.isComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Supabase is not configured. Add SUPABASE_URL and SUPABASE_ANON_KEY to .env.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _danger,
        ),
      );
      return;
    }

    setState(() => _isOnlineBackingUp = true);

    try {
      final backupPath = await DatabaseHelper.instance.createBackupArchive();
      final result = await const SupabaseBackupService().uploadBackup(
        config: config,
        backupPath: backupPath,
        storeName: _storeName,
      );
      await DatabaseHelper.instance.recordAuditLog(
        user: widget.currentUsername,
        action: 'backup_online',
        details: jsonEncode({
          'provider': 'supabase',
          'bucket': config.bucket.trim(),
          'object_path': result.objectPath,
          'bytes': result.bytes,
        }),
      );

      if (!mounted) return;
      await _saveLastOnlineBackupDate(DateTime.now());
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Online backup uploaded',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: SelectableText(
            '${config.bucket.trim()}/${result.objectPath}',
            style: TextStyle(color: _secondaryText),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Online backup failed: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isOnlineBackingUp = false);
      }
    }
  }

  Future<void> _restoreDatabase() async {
    HapticFeedback.lightImpact();

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['posbackup', 'db', 'zip'],
      allowMultiple: false,
      withData: true,
    );

    if (!mounted || result == null || result.files.isEmpty) return;

    final backup = result.files.single;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Restore database?',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This will replace the current products, sales, users, and settings with "${backup.name}". This action cannot be undone.',
          style: TextStyle(color: _secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Restore',
              style: TextStyle(color: _danger, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    setState(() => _isRestoring = true);

    try {
      final backupPath = backup.path;
      if (backupPath != null) {
        await DatabaseHelper.instance.restoreDatabaseFromPathWithAudit(
          backupPath: backupPath,
          user: widget.currentUsername,
        );
      } else if (backup.bytes != null) {
        await DatabaseHelper.instance.restoreDatabaseFromBytesWithAudit(
          bytes: backup.bytes!,
          user: widget.currentUsername,
          fileName: backup.name,
        );
      } else {
        throw Exception('Selected backup could not be read.');
      }

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Restore complete',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: Text(
            'The database has been restored. Reopen pages that were already loaded to see the latest data.',
            style: TextStyle(color: _secondaryText),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Restore failed: ${_restoreErrorMessage(e)}'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isRestoring = false);
      }
    }
  }

  String _restoreErrorMessage(Object error) {
    if (error is RestoreDatabaseException) {
      return error.message;
    }

    return error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  void _showClearDataDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Clear all data?',
          style: TextStyle(fontWeight: FontWeight.w700, color: _textPrimary),
        ),
        content: const Text(
          'This will permanently delete all products, sales, and settings. This action cannot be undone.',
          style: TextStyle(color: _textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: _textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Clear data',
              style: TextStyle(color: _danger, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _PinSetupDialog extends StatefulWidget {
  const _PinSetupDialog();

  @override
  State<_PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<_PinSetupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);
    bool saved;
    try {
      saved = await DatabaseHelper.instance.setOwnerPin(_pinController.text);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIN already used by another user'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (saved) {
      Navigator.pop(context, true);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not save PIN. Create an owner account first.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String? _validatePin(String? value) {
    if (value == null || value.isEmpty) return 'Enter a 4-digit PIN';
    if (value.length != 4) return 'PIN must be exactly 4 digits';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Set PIN login',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              decoration: InputDecoration(
                labelText: 'New PIN',
                hintText: '4 digits',
                prefixIcon: const Icon(Icons.pin_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: _validatePin,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmPinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              decoration: InputDecoration(
                labelText: 'Confirm PIN',
                hintText: 'Re-enter PIN',
                prefixIcon: const Icon(Icons.lock_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (value) {
                final pinError = _validatePin(value);
                if (pinError != null) return pinError;
                if (value != _pinController.text) return 'PINs do not match';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF667eea),
            foregroundColor: Colors.white,
          ),
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save PIN'),
        ),
      ],
    );
  }
}

// ─── Settings Row ─────────────────────────────────────────────────────────────
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.isLast = false,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isLast;

  static const Color _textPrimary = Color(0xFF1A1F36);
  static const Color _textSecondary = Color(0xFF6B7280);
  static const Color _textTertiary = Color(0xFFAAAAAA);
  static const Color _border = Color(0xFFEEEEEE);

  @override
  Widget build(BuildContext context) {
    final hasChevron = onTap != null && trailing == null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? const Color(0xFFF8FAFC) : _textPrimary;
    final secondaryText = isDark ? const Color(0xFFCBD5E1) : _textSecondary;
    final tertiaryText = isDark ? const Color(0xFF94A3B8) : _textTertiary;
    final dividerColor = isDark ? const Color(0xFF253047) : _border;
    final highlightColor = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFF4F5FF);

    return Column(
      children: [
        InkWell(
          onTap: onTap,
          splashColor: Colors.transparent,
          highlightColor: highlightColor,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 17, color: iconColor),
                ),

                const SizedBox(width: 12),

                // Label + subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(fontSize: 14, color: primaryText),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(fontSize: 12, color: secondaryText),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),

                // Trailing
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ] else if (hasChevron) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: tertiaryText,
                  ),
                ],
              ],
            ),
          ),
        ),

        // Divider (not on last row)
        if (!isLast)
          Padding(
            padding: const EdgeInsets.only(left: 58),
            child: Divider(height: 0.5, thickness: 0.5, color: dividerColor),
          ),
      ],
    );
  }
}

class _CloudSyncProgressRow extends StatelessWidget {
  const _CloudSyncProgressRow({
    required this.done,
    required this.total,
    required this.step,
  });

  final int done;
  final int total;
  final int step;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark
        ? const Color(0xFF253047)
        : const Color(0xFFEEEEEE);
    final secondaryText = isDark
        ? const Color(0xFFCBD5E1)
        : const Color(0xFF6B7280);
    final progress = total <= 0 ? null : (done / total).clamp(0.0, 1.0);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(58, 0, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                borderRadius: BorderRadius.circular(99),
              ),
              const SizedBox(height: 6),
              Text(
                total <= 0 ? 'Preparing sync...' : 'Sync progress: $step',
                style: TextStyle(fontSize: 11, color: secondaryText),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 58),
          child: Divider(height: 0.5, thickness: 0.5, color: dividerColor),
        ),
      ],
    );
  }
}
