import 'dart:async';
import 'package:pos_app/utils/message_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_app/database/database_helper.dart';
import 'package:pos_app/services/license_activation_service.dart';
import 'package:pos_app/theme/app_typography.dart';
import 'package:pos_app/utils/login_input_validator.dart';

import 'home.dart';
import 'pin_login.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    this.cloudRestoreLicenseKey,
    this.cloudRestoreStoreName,
    this.readOnly = false,
  });

  final String? cloudRestoreLicenseKey;
  final String? cloudRestoreStoreName;
  final bool readOnly;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const _loginSystemOverlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarContrastEnforced: false,
  );

  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _invalidCredentials = false;
  String? _cloudRestoreStatus;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() => _invalidCredentials = false);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final username = LoginInputValidator.sanitizeUsername(
      _usernameController.text,
    );
    final password = LoginInputValidator.sanitizePassword(
      _passwordController.text,
    );
    _usernameController.text = username;
    _passwordController.text = password;

    final restoringCloudLicense =
        widget.cloudRestoreLicenseKey?.trim().isNotEmpty == true;
    var user = restoringCloudLicense
        ? null
        : await DatabaseHelper.instance.login(username, password);

    if (restoringCloudLicense) {
      user = await _loginWithCloudOwner(username, password);
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    final loggedInUser = user;
    if (loggedInUser != null) {
      if (widget.readOnly && loggedInUser['role']?.toString() != 'admin') {
        setState(() => _invalidCredentials = true);
        _formKey.currentState!.validate();
        return;
      }
      if (!widget.readOnly) {
        await _bindLocalOwnerStoreIfNeeded(loggedInUser);
      }
      if (!mounted) return;
      if (!widget.readOnly) {
        unawaited(_rememberCloudSyncLogin(username, password));
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomePage(
            title: 'POS Dashboard',
            username: loggedInUser['username'] as String,
            role: loggedInUser['role'] as String,
            readOnly: widget.readOnly,
            initialSuccessMessage: 'Login successful',
          ),
        ),
      );
    } else {
      setState(() => _invalidCredentials = true);
      _formKey.currentState!.validate();
    }
  }

  Future<void> _bindLocalOwnerStoreIfNeeded(Map<String, dynamic> user) async {
    if (user['role']?.toString() != 'admin') return;

    final activation = await LicenseActivationService.instance
        .readLocalActivation();
    final storeId = activation?.storeId.trim() ?? '';
    if (storeId.isEmpty) return;

    final matches = await LicenseActivationService.instance
        .localOwnerMatchesStore(storeId);
    if (!matches) {
      await LicenseActivationService.instance.saveLocalOwnerStoreId(storeId);
    }
  }

  Future<Map<String, dynamic>?> _loginWithCloudOwner(
    String email,
    String password,
  ) async {
    if (!LoginInputValidator.isEmail(email)) {
      return null;
    }

    try {
      final localActivation = await LicenseActivationService.instance
          .readLocalActivation();
      final licenseKey =
          widget.cloudRestoreLicenseKey?.trim().isNotEmpty == true
          ? widget.cloudRestoreLicenseKey!.trim()
          : localActivation?.licenseKey.trim() ?? '';
      if (licenseKey.isEmpty) return null;

      late LicenseActivation activation;
      late int imported;
      await DatabaseHelper.instance.runWithCloudRestoreGuard(() async {
        activation = await LicenseActivationService.instance.activateStore(
          licenseKey: licenseKey,
          storeName:
              widget.cloudRestoreStoreName ??
              localActivation?.storeName ??
              'Restored Store',
          ownerName: email,
          email: email,
          password: password,
        );
        await LicenseActivationService.instance.saveCloudSyncCredentials(
          email: email,
          password: password,
        );
        if (mounted) {
          setState(() => _cloudRestoreStatus = 'Downloading cloud data');
        }
        imported = await DatabaseHelper.instance.pullCloudSnapshotToLocal(
          onProgress: (imported, total, status) {
            if (!mounted) return;
            setState(() {
              _cloudRestoreStatus = total > 0
                  ? '$status ($imported of $total)'
                  : status;
            });
          },
        );
      });
      await LicenseActivationService.instance.saveLocalOwnerStoreId(
        activation.storeId,
      );
      if (mounted) {
        setState(() {
          _cloudRestoreStatus =
              'Cloud data restored. $imported record${imported == 1 ? '' : 's'} retrieved.';
        });
        await Future<void>.delayed(const Duration(milliseconds: 1100));
      }

      return DatabaseHelper.instance.upsertOwnerFromCloud(
        email: email,
        password: password,
        storeName: activation.storeName,
        fullName: email,
      );
    } catch (_) {
      if (mounted) setState(() => _cloudRestoreStatus = null);
      return null;
    }
  }

  Future<void> _rememberCloudSyncLogin(String email, String password) async {
    if (!LoginInputValidator.isEmail(email)) {
      return;
    }

    try {
      await LicenseActivationService.instance.connectCloudSyncCredentials(
        email: email,
        password: password,
      );
    } catch (_) {
      // Local login should still succeed if cloud is temporarily unavailable.
    }
  }

  void _clearLoginError() {
    if (!_invalidCredentials) return;
    setState(() => _invalidCredentials = false);
  }

  String? _validateUsername(String? value) {
    return LoginInputValidator.validateUsername(value);
  }

  String? _validatePassword(String? value) {
    final error = LoginInputValidator.validatePassword(value);
    final password = LoginInputValidator.sanitizePassword(value ?? '');
    if (password.isNotEmpty && password.length < 6) {
      setState(() {
        _invalidCredentials = true;
      });
    }
    return error;
  }

  void _showMagicLinkDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => const _MagicLinkDialog(),
    );
  }

  void _openPinLogin() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PinLoginPage(readOnly: widget.readOnly),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF111827) : Colors.white;
    final fieldColor = isDark ? const Color(0xFF1E293B) : Colors.grey[50];
    final primaryText = isDark
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF333333);
    final secondaryText = isDark ? const Color(0xFFCBD5E1) : Colors.grey[600];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _loginSystemOverlayStyle,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        extendBodyBehindAppBar: true,
        body: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                ),
              ),
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    MediaQuery.of(context).padding.top + 24,
                    24,
                    MediaQuery.of(context).padding.bottom + 24,
                  ),
                  child: Card(
                    color: cardColor,
                    elevation: 12,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 16),
                            Image.asset(
                              'lib/assets/appiconnobg.png',
                              height: 150,
                              width: 250,
                              fit: BoxFit.cover,
                            ),
                            Text(
                              'Welcome Back!',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: primaryText,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Sign in to continue.',
                              style: TextStyle(
                                fontSize: 14,
                                color: secondaryText,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const _LicenseRenewalReminder(),
                            const SizedBox(height: 28),
                            TextFormField(
                              controller: _usernameController,
                              onChanged: (_) => _clearLoginError(),
                              inputFormatters: [
                                FilteringTextInputFormatter.deny(
                                  LoginInputValidator.usernameDeniedCharacters,
                                ),
                                LengthLimitingTextInputFormatter(
                                  LoginInputValidator.maxUsernameLength,
                                ),
                              ],
                              decoration: InputDecoration(
                                labelText: 'Username or email',
                                hintText: 'Enter your username or email',
                                prefixIcon: const Icon(Icons.person_outline),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: fieldColor,
                              ),
                              validator: _validateUsername,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordController,
                              onChanged: (_) => _clearLoginError(),
                              obscureText: _obscurePassword,
                              keyboardType: TextInputType.visiblePassword,
                              inputFormatters: [
                                FilteringTextInputFormatter.deny(
                                  LoginInputValidator.controlCharacters,
                                ),
                                LengthLimitingTextInputFormatter(
                                  LoginInputValidator.maxPasswordLength,
                                ),
                              ],
                              decoration: InputDecoration(
                                labelText: 'Password',
                                hintText: 'Enter your password',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: fieldColor,
                              ),
                              validator: _validatePassword,
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: !_invalidCredentials
                                  ? const SizedBox.shrink()
                                  : const Padding(
                                      padding: EdgeInsets.only(top: 12),
                                      child: MessageBanner(
                                        message:
                                            'Username or password is incorrect. Please check your credentials and try again.',
                                      ),
                                    ),
                            ),

                            const SizedBox(height: 8),
                            if (!widget.readOnly)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _showMagicLinkDialog,
                                  child: const Text('Email Magic Link'),
                                ),
                              ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF667eea),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 3,
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                    : const Text(
                                        'Sign In',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: OutlinedButton.icon(
                                onPressed: _openPinLogin,
                                icon: const Icon(Icons.pin_outlined),
                                label: const Text('PIN Login'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF667eea),
                                  side: const BorderSide(
                                    color: Color(0xFF667eea),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_cloudRestoreStatus != null)
              _CloudRestoreOverlay(status: _cloudRestoreStatus!),
          ],
        ),
      ),
    );
  }
}

class _LicenseRenewalReminder extends StatefulWidget {
  const _LicenseRenewalReminder();

  @override
  State<_LicenseRenewalReminder> createState() =>
      _LicenseRenewalReminderState();
}

class _LicenseRenewalReminderState extends State<_LicenseRenewalReminder> {
  Timer? _timer;
  LicenseActivation? _activation;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    _loadActivation();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _ticks++;
      if (_ticks % 15 == 0) {
        _loadActivation();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadActivation() async {
    final activation = await LicenseActivationService.instance
        .readLocalActivation();
    if (!mounted) return;
    setState(() => _activation = activation);
  }

  String _formatExpiry(DateTime expiry) {
    final local = expiry.toLocal();
    final hour = local.hour == 0
        ? 12
        : local.hour > 12
        ? local.hour - 12
        : local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    final month = const [
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
    ][local.month - 1];
    return '$month ${local.day}, ${local.year} at $hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final expiry = _activation?.licenseExpiresAt;
    if (expiry == null) return const SizedBox.shrink();

    final remaining = expiry.difference(DateTime.now());
    if (remaining <= Duration.zero || remaining > const Duration(days: 30)) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final urgent = remaining <= const Duration(days: 1);
    final accent = urgent ? const Color(0xFFDC2626) : const Color(0xFFD97706);
    final accentText = isDark
        ? urgent
              ? const Color(0xFFFCA5A5)
              : const Color(0xFFFCD34D)
        : accent;
    final background = isDark
        ? accent.withValues(alpha: 0.14)
        : accent.withValues(alpha: 0.07);
    final border = isDark
        ? accent.withValues(alpha: 0.38)
        : accent.withValues(alpha: 0.2);
    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    final minutes = remaining.inMinutes % 60;
    final seconds = remaining.inSeconds % 60;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.22 : 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.notifications_active_outlined,
                    size: 19,
                    color: accentText,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        urgent ? 'License expires soon' : 'Renewal reminder',
                        style: AppTypography.emphasizedBody.copyWith(
                          color: accentText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        urgent
                            ? 'Renew now to avoid interruptions at checkout.'
                            : 'Contact your administrator before the expiry date.',
                        style: AppTypography.caption.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'TIME REMAINING',
              style: AppTypography.smallCaption.copyWith(
                color: accentText,
                letterSpacing: 0.45,
              ),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: _CountdownUnit(value: days, label: 'Days'),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _CountdownUnit(value: hours, label: 'Hrs'),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _CountdownUnit(value: minutes, label: 'Min'),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _CountdownUnit(value: seconds, label: 'Sec'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Expires ${_formatExpiry(expiry)}',
              style: AppTypography.smallCaption.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountdownUnit extends StatelessWidget {
  const _CountdownUnit({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        children: [
          Text(
            value.toString().padLeft(2, '0'),
            style: AppTypography.cardTitle.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: AppTypography.smallCaption.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CloudRestoreOverlay extends StatelessWidget {
  const _CloudRestoreOverlay({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final completed = status.startsWith('Cloud data restored.');
    return ColoredBox(
      color: const Color(0x990F172A),
      child: Center(
        child: Container(
          width: 300,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (completed)
                const Icon(
                  Icons.cloud_done_rounded,
                  color: Color(0xFF16A34A),
                  size: 42,
                )
              else
                const CircularProgressIndicator(),
              const SizedBox(height: 18),
              Text(
                completed ? 'Cloud restore complete' : 'Retrieving cloud data',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                status,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MagicLinkDialog extends StatefulWidget {
  const _MagicLinkDialog();

  @override
  State<_MagicLinkDialog> createState() => _MagicLinkDialogState();
}

class _MagicLinkDialogState extends State<_MagicLinkDialog> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSending = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    final email = LoginInputValidator.sanitizeUsername(_emailController.text);
    _emailController.text = email;
    setState(() => _isSending = true);
    try {
      await LicenseActivationService.instance.sendMagicLinkEmail(email);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Magic link sent to $email'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Email Magic Link'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _emailController,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: InputDecoration(
                labelText: 'Email Address',
                hintText: 'Enter your email',
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              keyboardType: TextInputType.emailAddress,
              inputFormatters: [
                FilteringTextInputFormatter.deny(
                  LoginInputValidator.usernameDeniedCharacters,
                ),
                LengthLimitingTextInputFormatter(
                  LoginInputValidator.maxUsernameLength,
                ),
              ],
              validator: LoginInputValidator.validateEmail,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Color(0xFFDC2626),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFF991B1B),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF667eea),
          ),
          onPressed: _isSending ? null : _send,
          child: _isSending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Send', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
