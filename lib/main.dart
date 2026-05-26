import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_app/database/database_helper.dart';
import 'package:pos_app/services/env_config.dart';
import 'package:pos_app/services/license_activation_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pages/license_check_page.dart';
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
          return const LicenseCheckPage();
        }

        if (snapshot.hasError) {
          return const LicenseCheckPage();
        }

        return switch (snapshot.data) {
          _StartupState.ready => const LoginPage(),
          _ => const LicenseCheckPage(),
        };
      },
    );
  }

  Future<_StartupState> _resolveStartupState() async {
    final hasOwner = await DatabaseHelper.instance.hasOwnerAccount();
    if (!hasOwner) {
      return _StartupState.needsSetup;
    }

    if (await LicenseActivationService.instance.hasValidLocalActivation()) {
      return _StartupState.ready;
    }

    try {
      final activation = await LicenseActivationService.instance
          .recoverActivation();
      if (activation != null) {
        return _StartupState.ready;
      }
    } catch (_) {
      // No valid cloud activation: require license activation again.
    }
    return _StartupState.needsSetup;
  }
}

enum _StartupState { ready, needsSetup }
