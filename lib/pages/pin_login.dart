import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_app/database/database_helper.dart';

import 'home.dart';

class PinLoginPage extends StatefulWidget {
  const PinLoginPage({super.key, this.readOnly = false});

  final bool readOnly;

  @override
  State<PinLoginPage> createState() => _PinLoginPageState();
}

class _PinLoginPageState extends State<PinLoginPage>
    with SingleTickerProviderStateMixin {
  static const _overlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarContrastEnforced: false,
  );

  static const int _pinLength = 6;

  String _pin = '';
  bool _isLoading = false;
  bool _invalidPin = false;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _shakeAnimation =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0, end: -8), weight: 1),
          TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
          TweenSequenceItem(tween: Tween(begin: 8, end: -5), weight: 2),
          TweenSequenceItem(tween: Tween(begin: -5, end: 5), weight: 2),
          TweenSequenceItem(tween: Tween(begin: 5, end: 0), weight: 1),
        ]).animate(
          CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut),
        );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _enterDigit(String digit) {
    if (_pin.length >= _pinLength || _isLoading) return;
    final nextPin = _sanitizePin(_pin + digit);
    setState(() {
      _invalidPin = false;
      _pin = nextPin;
    });
    if (nextPin.length == _pinLength) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _login(auto: true);
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

  String _sanitizePin(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length <= _pinLength
        ? digits
        : digits.substring(0, _pinLength);
  }

  Future<void> _login({bool auto = false}) async {
    if (_isLoading) return;

    final pin = _sanitizePin(_pin);
    if (pin.length != _pinLength) {
      if (!auto) setState(() => _invalidPin = true);
      return;
    }
    setState(() => _pin = pin);

    setState(() {
      _isLoading = true;
      _invalidPin = false;
    });

    final user = await DatabaseHelper.instance.loginWithPin(pin);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (user == null) {
      HapticFeedback.mediumImpact();
      setState(() {
        _pin = '';
        _invalidPin = true;
      });
      _shakeController.forward(from: 0);
      return;
    }
    if (widget.readOnly && user['role']?.toString() != 'admin') {
      HapticFeedback.mediumImpact();
      setState(() {
        _pin = '';
        _invalidPin = true;
      });
      _shakeController.forward(from: 0);
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => HomePage(
          title: 'POS Dashboard',
          username: user['username'] as String,
          role: user['role'] as String,
          readOnly: widget.readOnly,
          initialSuccessMessage: 'Login successful',
        ),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cardColor = isDark ? const Color(0xFF111827) : Colors.white;
    final surfaceColor = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFF4F4F6);
    final primaryText = isDark
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF18181B);
    final secondaryText = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF71717A);
    final borderColor = isDark
        ? const Color(0xFF2D3748)
        : const Color(0xFFE4E4E7);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _overlayStyle,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        extendBodyBehindAppBar: true,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF6457D6), Color(0xFF9B5DE5)],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: borderColor, width: 0.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 32,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Back button
                      Align(
                        alignment: Alignment.centerLeft,
                        child: GestureDetector(
                          onTap: _isLoading
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.arrow_back_rounded,
                                size: 16,
                                color: secondaryText,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Back',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: secondaryText,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Icon ring
                      Center(
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF6457D6), Color(0xFF9B5DE5)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF6457D6,
                                ).withValues(alpha: 0.35),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.pin_outlined,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Title & subtitle
                      Text(
                        'Welcome back',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: primaryText,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Enter your 6-digit PIN to continue',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: secondaryText, fontSize: 13),
                      ),
                      const SizedBox(height: 28),

                      // PIN dots with shake
                      AnimatedBuilder(
                        animation: _shakeAnimation,
                        builder: (context, child) => Transform.translate(
                          offset: Offset(_shakeAnimation.value, 0),
                          child: child,
                        ),
                        child: _PinDots(
                          count: _pin.length,
                          maxCount: _pinLength,
                          invalid: _invalidPin,
                          activeColor: const Color(0xFF6457D6),
                          inactiveColor: borderColor,
                        ),
                      ),

                      // Error message
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _invalidPin
                            ? const Padding(
                                padding: EdgeInsets.only(top: 10),
                                child: Text(
                                  'Incorrect PIN — try again',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xFFE24B4A),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            : const SizedBox(height: 10),
                      ),
                      const SizedBox(height: 20),

                      // Keypad
                      _PinKeypad(
                        textColor: primaryText,
                        surfaceColor: surfaceColor,
                        borderColor: borderColor,
                        canSubmit: _pin.length == _pinLength && !_isLoading,
                        onDigit: _enterDigit,
                        onBackspace: _deleteDigit,
                        onSubmit: () => _login(),
                      ),

                      // Loading indicator
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _isLoading
                            ? const Padding(
                                padding: EdgeInsets.only(top: 20),
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF6457D6),
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox(height: 20),
                      ),
                    ],
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

// ─── Pin Dots ────────────────────────────────────────────────────────────────

class _PinDots extends StatelessWidget {
  const _PinDots({
    required this.count,
    required this.maxCount,
    required this.invalid,
    required this.activeColor,
    required this.inactiveColor,
  });

  final int count;
  final int maxCount;
  final bool invalid;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(maxCount, (i) {
        final active = i < count;
        final color = active
            ? (invalid ? const Color(0xFFE24B4A) : activeColor)
            : Colors.transparent;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: active ? 14 : 12,
          height: active ? 14 : 12,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: active
                  ? (invalid ? const Color(0xFFE24B4A) : activeColor)
                  : inactiveColor,
              width: 1.5,
            ),
          ),
        );
      }),
    );
  }
}

// ─── Pin Keypad ──────────────────────────────────────────────────────────────

class _PinKeypad extends StatelessWidget {
  const _PinKeypad({
    required this.textColor,
    required this.surfaceColor,
    required this.borderColor,
    required this.canSubmit,
    required this.onDigit,
    required this.onBackspace,
    required this.onSubmit,
  });

  final Color textColor;
  final Color surfaceColor;
  final Color borderColor;
  final bool canSubmit;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onSubmit;

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
              for (int i = 0; i < row.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: _PinKey(
                    label: row[i],
                    textColor: textColor,
                    surfaceColor: surfaceColor,
                    borderColor: borderColor,
                    onTap: () => onDigit(row[i]),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            // Submit
            Expanded(
              child: _PinKey(
                icon: Icons.check_rounded,
                tooltip: 'Submit PIN',
                textColor: Colors.white,
                surfaceColor: canSubmit
                    ? const Color(0xFF6457D6)
                    : surfaceColor,
                borderColor: canSubmit ? const Color(0xFF6457D6) : borderColor,
                opacity: canSubmit ? 1.0 : 0.38,
                onTap: canSubmit ? onSubmit : null,
              ),
            ),
            const SizedBox(width: 10),
            // 0
            Expanded(
              child: _PinKey(
                label: '0',
                textColor: textColor,
                surfaceColor: surfaceColor,
                borderColor: borderColor,
                onTap: () => onDigit('0'),
              ),
            ),
            const SizedBox(width: 10),
            // Backspace
            Expanded(
              child: _PinKey(
                icon: Icons.backspace_outlined,
                tooltip: 'Delete',
                textColor: textColor,
                surfaceColor: surfaceColor,
                borderColor: borderColor,
                onTap: onBackspace,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Pin Key ─────────────────────────────────────────────────────────────────

class _PinKey extends StatelessWidget {
  const _PinKey({
    required this.textColor,
    required this.surfaceColor,
    required this.borderColor,
    this.onTap,
    this.label,
    this.icon,
    this.tooltip,
    this.opacity = 1.0,
  });

  final String? label;
  final IconData? icon;
  final String? tooltip;
  final Color textColor;
  final Color surfaceColor;
  final Color borderColor;
  final VoidCallback? onTap;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? (label != null ? 'PIN $label' : ''),
      child: Opacity(
        opacity: opacity,
        child: Material(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            splashColor: Colors.white.withValues(alpha: 0.08),
            highlightColor: Colors.white.withValues(alpha: 0.04),
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor, width: 0.5),
              ),
              alignment: Alignment.center,
              child: icon == null
                  ? Text(
                      label!,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
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
