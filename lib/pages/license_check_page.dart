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
  bool _hasLicenseInput = false;
  String? _error;

  @override
  void dispose() {
    _licenseController.dispose();
    super.dispose();
  }

  Future<void> _checkLicense() async {
    setState(() => _error = null);
    if (!_hasLicenseInput) {
      _formKey.currentState?.validate();
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isChecking = true);
    try {
      final result = await LicenseActivationService.instance.checkLicenseKey(
        _licenseController.text,
      );

      if (!mounted) return;
      final existingStoreId = result.storeId?.trim() ?? '';
      final isExistingStoreLicense =
          existingStoreId.isNotEmpty &&
          (result.activated || result.restoreAvailable);

      if (isExistingStoreLicense) {
        final hasOwner = await DatabaseHelper.instance.hasOwnerAccount();
        final matchesStore = await LicenseActivationService.instance
            .localOwnerMatchesStore(existingStoreId);
        if (!mounted) return;

        if (hasOwner && matchesStore) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => LoginPage(
                cloudRestoreLicenseKey: result.licenseKey,
                cloudRestoreStoreName: result.storeName,
              ),
            ),
          );
          return;
        }

        if (!hasOwner || !matchesStore) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => OwnerSetupPage(
                verifiedLicenseKey: result.licenseKey,
                restoreExistingLicense: true,
                restoredStoreName: result.storeName,
              ),
            ),
          );
          return;
        }
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OwnerSetupPage(verifiedLicenseKey: result.licenseKey),
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
                          'Enter your license code. If this device was already activated, the app will restore it from server.',
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
                          onChanged: (value) {
                            final hasInput = value.trim().isNotEmpty;
                            if (hasInput != _hasLicenseInput ||
                                _error != null) {
                              setState(() {
                                _hasLicenseInput = hasInput;
                                _error = null;
                              });
                            }
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
                          _ErrorNotice(message: _error!),
                        ],
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isChecking || !_hasLicenseInput
                                ? null
                                : _checkLicense,
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
