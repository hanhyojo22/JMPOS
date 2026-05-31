import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_app/database/database_helper.dart';
import 'package:pos_app/services/env_config.dart';
import 'package:pos_app/services/license_activation_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pages/license_check_page.dart';
import 'pages/login.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EnvConfig.load();
  await _initializeSupabase();

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

class LicenseExpiredPage extends StatelessWidget {
  const LicenseExpiredPage({super.key});

  @override
  Widget build(BuildContext context) {
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
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'This license has expired. Please contact the admin to renew your subscription.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.4,
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
