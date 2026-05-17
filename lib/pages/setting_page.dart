import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_app/main.dart';

// ─── Settings Page ────────────────────────────────────────────────────────────
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // ── Design tokens ──────────────────────────────────────────────────────────
  static const Color _primary = Color(0xFF5C6BC0);
  static const Color _surface = Color(0xFFF4F5FF);
  static const Color _border = Color(0xFFEEEEEE);
  static const Color _textPrimary = Color(0xFF1A1F36);
  static const Color _textSecondary = Color(0xFF6B7280);
  static const Color _textTertiary = Color(0xFFAAAAAA);
  static const Color _danger = Color(0xFFDC2626);
  static const Color _dangerBg = Color(0xFFFEE2E2);
  static const Color _infoBg = Color(0xFFE6F1FB);
  static const Color _infoText = Color(0xFF185FA5);

  // ── Preferences state ──────────────────────────────────────────────────────
  bool _notifications = true;
  bool _darkMode = false;
  bool _barcodeScanner = true;
  bool _keepScreenOn = false;
  bool _loadedThemeValue = false;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _pageSurface => _isDark ? const Color(0xFF0F172A) : _surface;
  Color get _cardSurface => _isDark ? const Color(0xFF111827) : Colors.white;
  Color get _dividerColor => _isDark ? const Color(0xFF253047) : _border;
  Color get _primaryText => _isDark ? const Color(0xFFF8FAFC) : _textPrimary;
  Color get _secondaryText =>
      _isDark ? const Color(0xFFCBD5E1) : _textSecondary;
  Color get _tertiaryText => _isDark ? const Color(0xFF94A3B8) : _textTertiary;

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
                        subtitle: 'My Sari-Sari Store',
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
                        }),
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
                        subtitle: 'CSV · last exported 3 days ago',
                        onTap: () {},
                      ),
                      _SettingsRow(
                        icon: Icons.cloud_upload_outlined,
                        iconBg: const Color(0xFFEAF3DE),
                        iconColor: const Color(0xFF3B6D11),
                        label: 'Backup data',
                        subtitle: 'Auto-backup is on',
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildBadge('On', _infoBg, _infoText),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: _tertiaryText,
                            ),
                          ],
                        ),
                        onTap: () {},
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
              fontWeight: FontWeight.w700,
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
  Widget _buildToggle(bool value, ValueChanged<bool> onChanged) {
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
