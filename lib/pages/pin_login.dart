import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_app/database/database_helper.dart';

import 'home.dart';

class PinLoginPage extends StatefulWidget {
  const PinLoginPage({super.key});

  @override
  State<PinLoginPage> createState() => _PinLoginPageState();
}

class _PinLoginPageState extends State<PinLoginPage> {
  static const _pinSystemOverlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarContrastEnforced: false,
  );

  String _pin = '';
  bool _isLoading = false;
  bool _invalidPin = false;

  void _enterDigit(String digit) {
    if (_pin.length >= 4 || _isLoading) return;
    final nextPin = _pin + digit;
    setState(() {
      _invalidPin = false;
      _pin = nextPin;
    });
    if (nextPin.length == 4) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _login();
      });
    }
  }

  void _deleteDigit() {
    if (_pin.isEmpty || _isLoading) return;
    setState(() {
      _invalidPin = false;
      _pin = _pin.substring(0, _pin.length - 1);
    });
  }

  Future<void> _login() async {
    if (_pin.length != 4) {
      setState(() => _invalidPin = true);
      return;
    }

    setState(() {
      _isLoading = true;
      _invalidPin = false;
    });

    final user = await DatabaseHelper.instance.loginWithPin(_pin);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (user == null) {
      HapticFeedback.mediumImpact();
      setState(() {
        _pin = '';
        _invalidPin = true;
      });
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => HomePage(
          title: 'POS Dashboard',
          username: user['username'] as String,
          role: user['role'] as String,
        ),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF111827) : Colors.white;
    final fieldColor = isDark ? const Color(0xFF1E293B) : Colors.grey[50]!;
    final primaryText = isDark
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF333333);
    final secondaryText = isDark ? const Color(0xFFCBD5E1) : Colors.grey[600]!;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _pinSystemOverlayStyle,
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
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Card(
                  color: cardColor,
                  elevation: 12,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            tooltip: 'Back',
                            onPressed: _isLoading
                                ? null
                                : () => Navigator.of(context).pop(),
                            icon: Icon(
                              Icons.arrow_back_rounded,
                              color: primaryText,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Icon(
                          Icons.pin_outlined,
                          size: 56,
                          color: Color(0xFF667eea),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'PIN Login',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: primaryText,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Enter your PIN to continue.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: secondaryText, fontSize: 14),
                        ),
                        const SizedBox(height: 26),
                        _PinDots(
                          count: _pin.length,
                          invalid: _invalidPin,
                          activeColor: const Color(0xFF667eea),
                          inactiveColor: secondaryText.withValues(alpha: 0.25),
                        ),
                        if (_invalidPin) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Invalid PIN',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFFDC2626),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        _PinKeypad(
                          textColor: primaryText,
                          surfaceColor: fieldColor,
                          onDigit: _enterDigit,
                          onBackspace: _deleteDigit,
                        ),
                        if (_isLoading) ...[
                          const SizedBox(height: 22),
                          const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF667eea),
                              ),
                            ),
                          ),
                        ],
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

class _PinDots extends StatelessWidget {
  const _PinDots({
    required this.count,
    required this.invalid,
    required this.activeColor,
    required this.inactiveColor,
  });

  final int count;
  final bool invalid;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        final active = index < count;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: active ? 14 : 10,
          height: active ? 14 : 10,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            color: active
                ? invalid
                      ? const Color(0xFFDC2626)
                      : activeColor
                : inactiveColor,
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }
}

class _PinKeypad extends StatelessWidget {
  const _PinKeypad({
    required this.textColor,
    required this.surfaceColor,
    required this.onDigit,
    required this.onBackspace,
  });

  final Color textColor;
  final Color surfaceColor;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];

    return Column(
      children: [
        for (final row in rows) ...[
          Row(
            children: [
              for (final digit in row) ...[
                Expanded(
                  child: _PinKey(
                    label: digit,
                    textColor: textColor,
                    surfaceColor: surfaceColor,
                    onTap: () => onDigit(digit),
                  ),
                ),
                if (digit != row.last) const SizedBox(width: 10),
              ],
            ],
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            const Expanded(child: SizedBox(height: 54)),
            const SizedBox(width: 10),
            Expanded(
              child: _PinKey(
                label: '0',
                textColor: textColor,
                surfaceColor: surfaceColor,
                onTap: () => onDigit('0'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PinKey(
                icon: Icons.backspace_outlined,
                textColor: textColor,
                surfaceColor: surfaceColor,
                onTap: onBackspace,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PinKey extends StatelessWidget {
  const _PinKey({
    required this.textColor,
    required this.surfaceColor,
    required this.onTap,
    this.label,
    this.icon,
  });

  final String? label;
  final IconData? icon;
  final Color textColor;
  final Color surfaceColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label == null ? 'Backspace' : 'PIN $label',
      child: Material(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 54,
            child: Center(
              child: icon == null
                  ? Text(
                      label!,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  : Icon(icon, color: textColor, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}
