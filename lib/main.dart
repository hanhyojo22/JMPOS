import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'pages/login.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Modern safe area behavior
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(_lightSystemOverlayStyle);

  runApp(const MyApp());
}

const _lightSystemOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Color(0xFFF4F5FF),
  systemNavigationBarColor: Color(0xFFF4F5FF),
  systemNavigationBarDividerColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  systemNavigationBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemStatusBarContrastEnforced: false,
  systemNavigationBarContrastEnforced: false,
);

const _darkSystemOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Color(0xFF0F172A),
  systemNavigationBarColor: Color(0xFF0F172A),
  systemNavigationBarDividerColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  systemNavigationBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemStatusBarContrastEnforced: false,
  systemNavigationBarContrastEnforced: false,
);

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static MyAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<MyAppState>();

  @override
  State<MyApp> createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  bool isDarkMode = false;

  void toggleTheme(bool value) {
    SystemChrome.setSystemUIOverlayStyle(
      value ? _darkSystemOverlayStyle : _lightSystemOverlayStyle,
    );
    setState(() {
      isDarkMode = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDarkMode ? _darkSystemOverlayStyle : _lightSystemOverlayStyle,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,

        themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,

        theme: ThemeData(
          brightness: Brightness.light,
          primarySwatch: Colors.indigo,
          scaffoldBackgroundColor: const Color(0xFFF4F5FF),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFF4F5FF),
            foregroundColor: Color(0xFF1A1F36),
            elevation: 0,
            systemOverlayStyle: _lightSystemOverlayStyle,
          ),
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
            brightness: Brightness.light,
          ),
        ),

        darkTheme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0F172A),
          cardColor: const Color(0xFF111827),
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
            brightness: Brightness.dark,
            surface: const Color(0xFF111827),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF111827),
            foregroundColor: Color(0xFFF8FAFC),
            elevation: 0,
            systemOverlayStyle: _darkSystemOverlayStyle,
          ),
          dialogTheme: const DialogThemeData(
            backgroundColor: Color(0xFF111827),
            titleTextStyle: TextStyle(
              color: Color(0xFFF8FAFC),
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
            contentTextStyle: TextStyle(color: Color(0xFFCBD5E1)),
          ),
          bottomSheetTheme: const BottomSheetThemeData(
            backgroundColor: Color(0xFF111827),
            modalBackgroundColor: Color(0xFF111827),
          ),
          inputDecorationTheme: const InputDecorationTheme(
            filled: true,
            fillColor: Color(0xFF1E293B),
          ),
          textTheme: ThemeData.dark().textTheme.apply(
            bodyColor: Color(0xFFF8FAFC),
            displayColor: Color(0xFFF8FAFC),
          ),
        ),

        home: const LoginPage(),
      ),
    );
  }
}
