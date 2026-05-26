import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_app/database/database_helper.dart';
import 'package:pos_app/services/license_activation_service.dart';

import 'home.dart';

class OwnerSetupPage extends StatefulWidget {
  const OwnerSetupPage({
    super.key,
    this.activationRestored = false,
    this.verifiedLicenseKey,
    this.restoreExistingLicense = false,
    this.restoredStoreName,
  });

  final bool activationRestored;
  final String? verifiedLicenseKey;
  final bool restoreExistingLicense;
  final String? restoredStoreName;

  @override
  State<OwnerSetupPage> createState() => _OwnerSetupPageState();
}

class _OwnerSetupPageState extends State<OwnerSetupPage> {
  static const _setupOverlayStyle = SystemUiOverlayStyle(
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
  final _storeNameController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _pinController = TextEditingController();

  bool _isSaving = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _obscurePin = true;
  String? _error;

  @override
  void dispose() {
    _storeNameController.dispose();
    _ownerNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _completeSetup() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);

    final isRestoreExisting = widget.restoreExistingLicense;
    final email = _emailController.text.trim();
    final storeName = isRestoreExisting
        ? (widget.restoredStoreName?.trim().isNotEmpty == true
              ? widget.restoredStoreName!.trim()
              : 'Restored Store')
        : _storeNameController.text.trim();
    final ownerName = isRestoreExisting
        ? email
        : _ownerNameController.text.trim();
    final password = _passwordController.text;
    final pin = _pinController.text.trim();
    if (!widget.activationRestored) {
      final inviteCode = widget.verifiedLicenseKey?.trim().toUpperCase() ?? '';
      if (inviteCode.isEmpty) {
        setState(() {
          _isSaving = false;
          _error = 'Verify a license before creating the owner account.';
        });
        return;
      }
      try {
        await LicenseActivationService.instance.activateStore(
          licenseKey: inviteCode,
          storeName: storeName,
          ownerName: ownerName,
          email: email,
          password: password,
        );
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isSaving = false;
          _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        });
        return;
      }
    }

    final userId = await DatabaseHelper.instance.createOwner(
      username: email,
      password: password,
      email: email,
      storeName: storeName,
      fullName: ownerName,
    );

    if (!mounted) return;

    if (userId <= 0) {
      setState(() {
        _isSaving = false;
        _error = 'Could not create owner account. Username may already exist.';
      });
      return;
    }

    try {
      final savedPin = await DatabaseHelper.instance.setOwnerPin(pin);
      if (!savedPin) {
        throw Exception('Could not save owner PIN.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      });
      return;
    }

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomePage(
          title: 'POS Dashboard',
          username: email.toLowerCase(),
          role: 'admin',
        ),
      ),
    );
  }

  String? _required(String? value, String label) {
    if (value == null || value.trim().isEmpty) return '$label is required';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 6) return 'Use at least 6 characters';
    return null;
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Owner email is required';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    final passwordError = _validatePassword(value);
    if (passwordError != null) return passwordError;
    if (value != _passwordController.text) return 'Passwords do not match';
    return null;
  }

  String? _validatePin(String? value) {
    final pin = value?.trim() ?? '';
    if (pin.isEmpty) return 'Owner PIN is required';
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      return 'PIN must be 4 to 6 digits';
    }
    return null;
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    String? hint,
    Widget? suffixIcon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: isDark ? const Color(0xFF1E293B) : Colors.grey[50],
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF667EEA), width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF111827) : Colors.white;
    final primaryText = isDark
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF1A1F36);
    final secondaryText = isDark ? const Color(0xFFCBD5E1) : Colors.grey[600];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _setupOverlayStyle,
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
                  padding: const EdgeInsets.all(28),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: const BoxDecoration(
                            color: Color(0xFF667EEA),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.storefront_rounded,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Set up your store',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: primaryText,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.activationRestored
                              ? 'Cloud activation was restored. Create the local owner account for this device.'
                              : widget.restoreExistingLicense
                              ? 'This license already belongs to an existing store. Sign in with the original owner account to restore it on this device.'
                              : 'Register the owner account for local POS access and Supabase Cloud Sync.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: secondaryText,
                            fontSize: 14,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 26),
                        if (!widget.restoreExistingLicense) ...[
                          TextFormField(
                            controller: _storeNameController,
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(80),
                            ],
                            decoration: _fieldDecoration(
                              label: 'Store name',
                              hint: 'e.g. My Sari-Sari Store',
                              icon: Icons.store_mall_directory_outlined,
                            ),
                            validator: (value) =>
                                _required(value, 'Store name'),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _ownerNameController,
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(80),
                            ],
                            decoration: _fieldDecoration(
                              label: 'Owner full name',
                              hint: 'Juan Dela Cruz',
                              icon: Icons.person_outline_rounded,
                            ),
                            validator: (value) =>
                                _required(value, 'Owner full name'),
                          ),
                          const SizedBox(height: 14),
                        ],
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [
                            FilteringTextInputFormatter.deny(
                              RegExp(r'[\u0000-\u001F\u007F\s]'),
                            ),
                            LengthLimitingTextInputFormatter(80),
                          ],
                          decoration: _fieldDecoration(
                            label: widget.restoreExistingLicense
                                ? 'Original owner email'
                                : 'Owner email',
                            hint: 'owner@example.com',
                            icon: Icons.email_outlined,
                          ),
                          validator: _validateEmail,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.next,
                          decoration: _fieldDecoration(
                            label: widget.restoreExistingLicense
                                ? 'Original owner password'
                                : 'Password',
                            hint: 'At least 6 characters',
                            icon: Icons.lock_outline_rounded,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                          validator: _validatePassword,
                        ),
                        if (!widget.restoreExistingLicense) ...[
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: _obscureConfirmPassword,
                            textInputAction: TextInputAction.next,
                            decoration: _fieldDecoration(
                              label: 'Confirm password',
                              hint: 'Re-enter password',
                              icon: Icons.lock_outline_rounded,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirmPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                onPressed: () => setState(
                                  () => _obscureConfirmPassword =
                                      !_obscureConfirmPassword,
                                ),
                              ),
                            ),
                            validator: _validateConfirmPassword,
                          ),
                        ],
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _pinController,
                          obscureText: _obscurePin,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          decoration: _fieldDecoration(
                            label: 'Owner PIN',
                            hint: '4 to 6 digits',
                            icon: Icons.pin_outlined,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePin
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                              onPressed: () =>
                                  setState(() => _obscurePin = !_obscurePin),
                            ),
                          ),
                          validator: _validatePin,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          _ErrorNotice(message: _error!),
                        ],
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _completeSetup,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF667eea),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color(
                                0xFF667eea,
                              ).withValues(alpha: 0.6),
                              elevation: 3,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    widget.activationRestored
                                        ? 'Restore Local Owner'
                                        : widget.restoreExistingLicense
                                        ? 'Restore Existing Store'
                                        : 'Register Store',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
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

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          const Icon(Icons.info_outline, color: Color(0xFFDC2626), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
