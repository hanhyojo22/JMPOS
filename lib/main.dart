import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_app/database/database_helper.dart';
import 'package:pos_app/services/env_config.dart';
import 'package:pos_app/services/license_activation_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pages/login.dart';
import 'pages/owner_setup.dart';

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
    if (Supabase.instance.client.auth.currentSession == null) {
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
          return const LicenseSplashScreen();
        }

        if (snapshot.hasError) {
          return const LoginPage();
        }

        return switch (snapshot.data) {
          _StartupState.ready => const LoginPage(),
          _StartupState.needsLocalOwner => const OwnerSetupPage(
            activationRestored: true,
          ),
          _ => const OwnerSetupPage(),
        };
      },
    );
  }

  Future<_StartupState> _resolveStartupState() async {
    final hasOwner = await DatabaseHelper.instance.hasOwnerAccount();
    if (!hasOwner) {
      try {
        final activation =
            await LicenseActivationService.instance.recoverActivation();
        if (activation != null) {
          return _StartupState.needsLocalOwner;
        }
      } catch (_) {
        // No network or no matching cloud activation: show first-install setup.
      }
      return _StartupState.needsSetup;
    }

    if (await LicenseActivationService.instance.hasValidLocalActivation()) {
      return _StartupState.ready;
    }

    try {
      await LicenseActivationService.instance.recoverActivation();
    } catch (_) {
      // Existing activated installs keep working during local/offline use.
    }
    return _StartupState.ready;
  }
}

enum _StartupState { ready, needsSetup, needsLocalOwner }

class LicenseSplashScreen extends StatelessWidget {
  const LicenseSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Icon(
                    Icons.storefront_rounded,
                    color: Colors.white,
                    size: 42,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'TindaPOS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Checking license and device activation',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 28),
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
