import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_app/database/database_helper.dart';
import 'package:pos_app/services/env_config.dart';
import 'package:pos_app/services/license_activation_service.dart';
import 'package:pos_app/services/screen_awake_service.dart';
import 'package:pos_app/theme/app_typography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'pages/license_check_page.dart';
import 'pages/login.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EnvConfig.load();
  await _initializeSupabase();
  await ScreenAwakeService.instance.initialize();

  // Modern safe area behavior
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  runApp(const MyApp());
}

Future<void> _initializeSupabase() async {
  final supabaseUrl = EnvConfig.supabaseUrl;
  final supabaseAnonKey = EnvConfig.supabaseAnonKey;

  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) return;

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static MyAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<MyAppState>();

  @override
  State<MyApp> createState() => MyAppState();
}

class MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  Timer? _cloudSyncTimer;
  Timer? _licenseRefreshTimer;
  Timer? _licenseExpiryTimer;
  bool _backgroundCloudSyncRunning = false;
  bool _licenseRefreshRunning = false;
  bool _showingExpiredLicense = false;
  bool _localSnapshotQueuedForCloudSync = false;
  bool isDarkMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_syncCloudInBackground(queueLocalSnapshot: true));
    _cloudSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_syncCloudInBackground());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshLicenseEnforcement());
    });
    _licenseRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(_refreshLicenseEnforcement());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cloudSyncTimer?.cancel();
    _licenseRefreshTimer?.cancel();
    _licenseExpiryTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncCloudInBackground());
      unawaited(_refreshLicenseEnforcement());
    }
  }

  Future<void> _refreshLicenseEnforcement() async {
    if (_licenseRefreshRunning) return;
    _licenseRefreshRunning = true;
    try {
      final service = LicenseActivationService.instance;
      final localActivation = await service.readLocalActivation();
      if (localActivation == null) return;
      if (localActivation.isExpired) {
        _showExpiredLicense();
      } else {
        _scheduleLicenseExpiry(localActivation);
      }
      try {
        final refreshed = await service.refreshLicenseStatus();
        if (refreshed == null) return;
        if (refreshed.isExpired) {
          _showExpiredLicense();
          return;
        }
        _scheduleLicenseExpiry(refreshed);
        if (_showingExpiredLicense) {
          _showRenewedLogin();
        }
      } catch (e) {
        if (e.toString().toLowerCase().contains('expired')) {
          _showExpiredLicense();
        }
      }
    } finally {
      _licenseRefreshRunning = false;
    }
  }

  void _scheduleLicenseExpiry(LicenseActivation activation) {
    _licenseExpiryTimer?.cancel();
    final expiry = activation.licenseExpiresAt;
    if (expiry == null) return;
    final delay = expiry.difference(DateTime.now());
    if (delay <= Duration.zero) {
      _showExpiredLicense();
      return;
    }
    _licenseExpiryTimer = Timer(delay, _showExpiredLicense);
  }

  void _showExpiredLicense() {
    if (_showingExpiredLicense) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    _showingExpiredLicense = true;
    _licenseExpiryTimer?.cancel();
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LicenseExpiredPage()),
      (_) => false,
    );
  }

  void _showRenewedLogin() {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    _showingExpiredLicense = false;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  Future<void> _syncCloudInBackground({bool queueLocalSnapshot = false}) async {
    if (_backgroundCloudSyncRunning) return;
    if (EnvConfig.supabaseUrl.isEmpty || EnvConfig.supabaseAnonKey.isEmpty) {
      return;
    }
    final activation = await LicenseActivationService.instance
        .readLocalActivation();
    if (activation?.isExpired == true) return;
    final cloudSignedIn = await LicenseActivationService.instance
        .ensureCloudSyncSignedIn();
    if (!cloudSignedIn) {
      return;
    }

    _backgroundCloudSyncRunning = true;
    try {
      if (queueLocalSnapshot || !_localSnapshotQueuedForCloudSync) {
        await DatabaseHelper.instance.queueLocalSnapshotForSync();
        _localSnapshotQueuedForCloudSync = true;
      }
      await DatabaseHelper.instance.syncPendingChanges();
    } catch (e) {
      debugPrint('Background cloud sync failed: $e');
    } finally {
      _backgroundCloudSyncRunning = false;
    }
  }

  void toggleTheme(bool value) {
    setState(() {
      isDarkMode = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final overlayStyle = isDarkMode
        ? SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
          )
        : SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        debugShowCheckedModeBanner: false,
        themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,

        theme: ThemeData(
          brightness: Brightness.light,
          primarySwatch: Colors.indigo,
          scaffoldBackgroundColor: const Color(0xFFF4F5FF),
          textTheme: AppTypography.textTheme(
            primaryColor: const Color(0xFF1A1F36),
            secondaryColor: const Color(0xFF6B7280),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            systemOverlayStyle: SystemUiOverlayStyle.dark,
          ),
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
            brightness: Brightness.light,
          ),
        ),

        darkTheme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0F172A),
          textTheme: AppTypography.textTheme(
            primaryColor: const Color(0xFFF8FAFC),
            secondaryColor: const Color(0xFFCBD5E1),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            foregroundColor: Color(0xFFF8FAFC),
            systemOverlayStyle: SystemUiOverlayStyle.light,
          ),
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
            brightness: Brightness.dark,
          ),
        ),

        home: const StartupGate(),
      ),
    );
  }
}

class StartupGate extends StatelessWidget {
  const StartupGate({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StartupState>(
      future: _resolveStartupState(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const StartupBlankScreen();
        }

        if (snapshot.hasError) {
          return const LicenseCheckPage();
        }

        return switch (snapshot.data) {
          _StartupState.ready => const LoginPage(),
          _StartupState.expired => const LicenseExpiredPage(),
          _ => const LicenseCheckPage(),
        };
      },
    );
  }

  Future<_StartupState> _resolveStartupState() async {
    final hasOwner = await DatabaseHelper.instance.hasOwnerAccount();
    final licenseService = LicenseActivationService.instance;

    final localActivation = await licenseService.readLocalActivation();
    if (localActivation?.isExpired == true) return _StartupState.expired;
    if (localActivation != null &&
        DateTime.now().difference(localActivation.lastVerifiedAt) <=
            const Duration(days: 14)) {
      return _stateForActivation(hasOwner, localActivation);
    }

    try {
      final activation = await licenseService.recoverActivation();
      if (activation != null) {
        return _stateForActivation(hasOwner, activation);
      }
    } catch (error) {
      if (error.toString().toLowerCase().contains('expired')) {
        return _StartupState.expired;
      }
      // No valid cloud activation: require license activation again.
    }
    return _StartupState.needsSetup;
  }

  Future<_StartupState> _stateForActivation(
    bool hasOwner,
    LicenseActivation activation,
  ) async {
    if (!hasOwner) return _StartupState.needsSetup;

    final licenseService = LicenseActivationService.instance;
    final localOwnerStoreId = await licenseService.readLocalOwnerStoreId();
    if (localOwnerStoreId == activation.storeId) return _StartupState.ready;

    return _StartupState.needsSetup;
  }
}

enum _StartupState { ready, needsSetup, expired }

class LicenseExpiredPage extends StatefulWidget {
  const LicenseExpiredPage({super.key});

  @override
  State<LicenseExpiredPage> createState() => _LicenseExpiredPageState();
}

class _LicenseExpiredPageState extends State<LicenseExpiredPage> {
  Timer? _renewalCheckTimer;
  bool _checking = false;
  bool _backgroundCheckRunning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _renewalCheckTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(_checkAgain(background: true));
    });
  }

  @override
  void dispose() {
    _renewalCheckTimer?.cancel();
    super.dispose();
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

  Future<void> _checkAgain({bool background = false}) async {
    if (_checking || _backgroundCheckRunning) return;
    if (background) {
      _backgroundCheckRunning = true;
    } else {
      setState(() {
        _checking = true;
        _error = null;
      });
    }
    try {
      final activation = await LicenseActivationService.instance
          .recoverActivation();
      if (!mounted) return;
      if (activation == null || activation.isExpired) {
        if (!background) {
          setState(
            () => _error = 'License is still expired. Please renew it first.',
          );
        }
        return;
      }
      _renewalCheckTimer?.cancel();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      if (!background) {
        final stillExpired = e.toString().toLowerCase().contains('expired');
        setState(() {
          _error = stillExpired
              ? 'License is still expired. Please renew it first.'
              : 'Could not verify the renewal. Check your internet connection and try again.';
        });
      }
    } finally {
      if (background) {
        _backgroundCheckRunning = false;
      } else if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _contactAdmin() async {
    final phone = EnvConfig.supportPhone.trim();
    if (phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri) && mounted) {
      setState(() => _error = 'Could not open the phone dialer.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = EnvConfig.supportPhone.trim();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    const danger = Color(0xFFDC2626);
    const dangerDark = Color(0xFFFCA5A5);
    final dangerText = isDark ? dangerDark : danger;
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final surfaceMuted = isDark
        ? const Color(0xFF111827)
        : const Color(0xFFF8FAFC);
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE5E7EB);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 40,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: borderColor),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.18 : 0.08,
                            ),
                            blurRadius: 28,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: danger.withValues(
                                alpha: isDark ? 0.18 : 0.08,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.error_outline_rounded,
                                  size: 16,
                                  color: dangerText,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'LICENSE EXPIRED',
                                  style: AppTypography.smallCaption.copyWith(
                                    color: dangerText,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              color: danger.withValues(
                                alpha: isDark ? 0.18 : 0.08,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.lock_clock_outlined,
                              size: 38,
                              color: dangerText,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Your license has expired',
                            textAlign: TextAlign.center,
                            style: AppTypography.pageTitle.copyWith(
                              color: colors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Renew your subscription to restore selling and editing. Your records remain safe.',
                            textAlign: TextAlign.center,
                            style: AppTypography.body.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 20),
                          FutureBuilder<LicenseActivation?>(
                            future: LicenseActivationService.instance
                                .readLocalActivation(),
                            builder: (context, snapshot) {
                              final expiry = snapshot.data?.licenseExpiresAt;
                              if (expiry == null) {
                                return const SizedBox.shrink();
                              }
                              return Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: surfaceMuted,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.calendar_today_outlined,
                                      size: 19,
                                      color: colors.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Expired on',
                                            style: AppTypography.caption
                                                .copyWith(
                                                  color:
                                                      colors.onSurfaceVariant,
                                                ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _formatExpiry(expiry),
                                            style: AppTypography.emphasizedBody
                                                .copyWith(
                                                  color: colors.onSurface,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: colors.primary.withValues(
                                alpha: isDark ? 0.16 : 0.06,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 20,
                                  color: colors.primary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    phone.isEmpty
                                        ? 'Ask your administrator to renew the license, then tap Check Again.'
                                        : 'Contact your administrator for renewal, then tap Check Again to unlock the POS.',
                                    style: AppTypography.caption.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'This screen checks for renewal automatically every 15 seconds.',
                            textAlign: TextAlign.center,
                            style: AppTypography.smallCaption.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: danger.withValues(
                                  alpha: isDark ? 0.18 : 0.07,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    size: 18,
                                    color: dangerText,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: AppTypography.caption.copyWith(
                                        color: dangerText,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: FilledButton.icon(
                              onPressed: _checking ? null : () => _checkAgain(),
                              icon: _checking
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.refresh_rounded),
                              label: Text(
                                _checking
                                    ? 'Checking license...'
                                    : 'Check Again',
                              ),
                            ),
                          ),
                          if (phone.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: OutlinedButton.icon(
                                onPressed: _contactAdmin,
                                icon: const Icon(Icons.call_outlined),
                                label: const Text('Contact Admin'),
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          TextButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const LoginPage(readOnly: true),
                                ),
                              );
                            },
                            icon: const Icon(Icons.visibility_outlined),
                            label: const Text('View records in read-only mode'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class StartupBlankScreen extends StatelessWidget {
  const StartupBlankScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF4F5FF),
    );
  }
}
