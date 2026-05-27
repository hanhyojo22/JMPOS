import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_app/database/database_helper.dart';
import 'package:pos_app/services/license_activation_service.dart';

import 'home.dart';
import 'pin_login.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    this.cloudRestoreLicenseKey,
    this.cloudRestoreStoreName,
  });

  final String? cloudRestoreLicenseKey;
  final String? cloudRestoreStoreName;

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
  static const int _maxUsernameLength = 80;
  static const int _maxPasswordLength = 128;

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
    final username = _sanitizeUsername(_usernameController.text);
    final password = _sanitizePassword(_passwordController.text);
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
      await _bindLocalOwnerStoreIfNeeded(loggedInUser);
      if (!mounted) return;
      unawaited(_rememberCloudSyncLogin(username, password));
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomePage(
            title: 'POS Dashboard',
            username: loggedInUser['username'] as String,
            role: loggedInUser['role'] as String,
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
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
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

      final activation = await LicenseActivationService.instance.activateStore(
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
      await DatabaseHelper.instance.pullCloudSnapshotToLocal();
      await LicenseActivationService.instance.saveLocalOwnerStoreId(
        activation.storeId,
      );

      return DatabaseHelper.instance.upsertOwnerFromCloud(
        email: email,
        password: password,
        storeName: activation.storeName,
        fullName: email,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _rememberCloudSyncLogin(String email, String password) async {
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return;
    }

    try {
      await LicenseActivationService.instance.saveCloudSyncCredentials(
        email: email,
        password: password,
      );
      await LicenseActivationService.instance.ensureCloudSyncSignedIn();
    } catch (_) {
      // Local login should still succeed if cloud is temporarily unavailable.
    }
  }

  void _clearLoginError() {
    if (!_invalidCredentials) return;
    setState(() => _invalidCredentials = false);
  }

  String _sanitizeUsername(String value) {
    return value
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '')
        .trim()
        .toLowerCase();
  }

  String _sanitizePassword(String value) {
    return value.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '');
  }

  String? _validateUsername(String? value) {
    final username = _sanitizeUsername(value ?? '');
    final isEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(username);
    if (username.isEmpty) return 'Please enter your username or email';
    if (username.length < 3) return 'Login must be at least 3 characters';
    if (username.length > _maxUsernameLength) return 'Username is too long';
    if (!isEmail && !RegExp(r'^[a-z0-9_]+$').hasMatch(username)) {
      return 'Use a username or valid email';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final password = _sanitizePassword(value ?? '');
    if (password.isEmpty) return 'Please enter your password';
    if (password.length < 6) return 'Password must be at least 6 characters';
    if (password.length > _maxPasswordLength) return 'Password is too long';
    return null;
  }

  void _showMagicLinkDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => const _MagicLinkDialog(),
    );
  }

  void _openPinLogin() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PinLoginPage()));
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
        body: Container(
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
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: primaryText,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sign in to continue.',
                          style: TextStyle(fontSize: 15, color: secondaryText),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28),
                        TextFormField(
                          controller: _usernameController,
                          onChanged: (_) => _clearLoginError(),
                          inputFormatters: [
                            FilteringTextInputFormatter.deny(
                              RegExp(r'[\u0000-\u001F\u007F\s]'),
                            ),
                            LengthLimitingTextInputFormatter(
                              _maxUsernameLength,
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
                              RegExp(r'[\u0000-\u001F\u007F]'),
                            ),
                            LengthLimitingTextInputFormatter(
                              _maxPasswordLength,
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
                                  child: _LoginErrorNotice(
                                    message:
                                        'Username or password is incorrect. Please check your credentials and try again.',
                                  ),
                                ),
                        ),
                        const SizedBox(height: 8),
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
                                      valueColor: AlwaysStoppedAnimation<Color>(
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
                              side: const BorderSide(color: Color(0xFF667eea)),
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
      ),
    );
  }
}

class _LoginErrorNotice extends StatelessWidget {
  const _LoginErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFDC2626),
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF991B1B),
                fontSize: 13,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
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

    final email = _emailController.text.trim();
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
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your email';
                }
                if (!RegExp(
                  r'^[\w\-.]+@([\w-]+\.)+[\w-]{2,4}$',
                ).hasMatch(value)) {
                  return 'Please enter a valid email';
                }
                return null;
              },
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
