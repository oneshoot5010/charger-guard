import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'api.dart';
import 'screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (d) {
    FlutterError.presentError(d);
    Api.log('FlutterError: ${d.exceptionAsString()}\n${d.stack}');
  };
  PlatformDispatcher.instance.onError = (e, s) {
    Api.log('Uncaught: $e\n$s');
    return true;
  };
  try {
    final s = await Api.settings();
    themeMode.value = (s['theme'] ?? 'system') as String;
  } catch (_) {}
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  ThemeData _theme(Brightness b) {
    final dark = b == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFF5A623), brightness: b),
      scaffoldBackgroundColor: dark ? const Color(0xFF14110B) : const Color(0xFFFFF9EE),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? const Color(0xFF221D13) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: themeMode,
      builder: (_, m, __) => MaterialApp(
        title: 'حارس الشاحن',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: m == 'dark'
            ? ThemeMode.dark
            : m == 'light'
                ? ThemeMode.light
                : ThemeMode.system,
        home: const Shell(),
      ),
    );
  }
}
