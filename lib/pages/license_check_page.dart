import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_app/database/database_helper.dart';
import 'package:pos_app/services/license_activation_service.dart';

import 'login.dart';
import 'owner_setup.dart';

class LicenseCheckPage extends StatefulWidget {
  const LicenseCheckPage({super.key});

  @override
  State<LicenseCheckPage> createState() => _LicenseCheckPageState();
}

class _LicenseCheckPageState extends State<LicenseCheckPage> {
  final _formKey = GlobalKey<FormState>();
  final _licenseController = TextEditingController();
  bool _isChecking = false;
  String? _error;

  @override
  void dispose() {
    _licenseController.dispose();
    super.dispose();
  }

  Future<void> _checkLicense() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isChecking = true);
    try {
      final result = await LicenseActivationService.instance.checkLicenseKey(
        _licenseController.text,
      );

      if (!mounted) return;
      if (result.activated) {
        final hasOwner = await DatabaseHelper.instance.hasOwnerAccount();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => hasOwner
                ? const LoginPage()
                : const OwnerSetupPage(activationRestored: true),
          ),
        );
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OwnerSetupPage(
            verifiedLicenseKey: result.licenseKey,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      });
    }
  }

  String? _validateLicense(String? value) {
    final code = value?.trim() ?? '';
    if (code.isEmpty) return 'License code is required';
    if (code.length < 4) return 'Code is too short';
    if (code.length > 40) return 'Code is too long';
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(code)) {
      return 'Use letters, numbers, dash, or underscore only';
    }
    return null;
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
      value: SystemUiOverlayStyle.light,
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
                            Icons.vpn_key_rounded,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Activate License',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: primaryText,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Enter your license code. If this device was already activated, the app will restore it from Supabase.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: secondaryText,
                            fontSize: 14,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 26),
                        TextFormField(
                          controller: _licenseController,
                          textCapitalization: TextCapitalization.characters,
                          textInputAction: TextInputAction.done,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[a-zA-Z0-9_-]'),
                            ),
                            LengthLimitingTextInputFormatter(40),
                          ],
                          onFieldSubmitted: (_) {
                            if (!_isChecking) _checkLicense();
                          },
                          decoration: InputDecoration(
                            labelText: 'License code',
                            hintText: 'ABCD-1234',
                            prefixIcon: const Icon(Icons.vpn_key_outlined),
                            filled: true,
                            fillColor: isDark
                                ? const Color(0xFF1E293B)
                                : Colors.grey[50],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: _validateLicense,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            _error!,
                            style: const TextStyle(
                              color: Color(0xFFDC2626),
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isChecking ? null : _checkLicense,
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
                            child: _isChecking
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Continue',
                                    style: TextStyle(
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
