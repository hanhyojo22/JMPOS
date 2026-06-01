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
  Timer? _cloudSyncTimer;
  bool _backgroundCloudSyncRunning = false;
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cloudSyncTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncCloudInBackground());
    }
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
  bool _checking = false;
  String? _error;

  Future<void> _checkAgain() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final activation = await LicenseActivationService.instance
          .recoverActivation();
      if (!mounted) return;
      if (activation == null || activation.isExpired) {
        setState(
          () => _error = 'License is still expired. Please renew it first.',
        );
        return;
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error =
            'Could not verify the renewal. Check your internet connection and try again.';
      });
    } finally {
      if (mounted) setState(() => _checking = false);
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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.event_busy_outlined,
                    size: 64,
                    color: Color(0xFFDC2626),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'License expired',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    phone.isEmpty
                        ? 'This license has expired. Please contact the admin to renew your subscription.'
                        : 'This license has expired. Contact the admin to renew your subscription, then check again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<LicenseActivation?>(
                    future: LicenseActivationService.instance
                        .readLocalActivation(),
                    builder: (context, snapshot) {
                      final expiry = snapshot.data?.licenseExpiresAt;
                      if (expiry == null) return const SizedBox.shrink();
                      return Text(
                        'Expired on ${expiry.toLocal().toString().split(' ').first}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFDC2626)),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (phone.isNotEmpty) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _contactAdmin,
                        icon: const Icon(Icons.call_outlined),
                        label: const Text('Contact Admin'),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _checking ? null : _checkAgain,
                      icon: _checking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: const Text('Check Again'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LoginPage(readOnly: true),
                          ),
                        );
                      },
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('View Records'),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
