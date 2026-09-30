import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'src/screens/login.dart';
import 'src/screens/shell.dart';
import 'src/state.dart';
import 'src/ui.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() => runApp(ChangeNotifierProvider(create: (_) => AppState()..init(), child: const ParkSpaceApp()));

class ParkSpaceApp extends StatelessWidget {
  const ParkSpaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: brand).copyWith(primary: brand, onPrimary: Colors.white);
    return MaterialApp(
      title: 'ParkSpace',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F6FB),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white, surfaceTintColor: Colors.white, elevation: 0, scrolledUnderElevation: 1,
        ),
        cardTheme: CardThemeData(
          color: Colors.white, elevation: 0, margin: EdgeInsets.zero, surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE6E9F2))),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD9DDE8))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD9DDE8))),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
        navigationBarTheme: const NavigationBarThemeData(backgroundColor: Colors.white, surfaceTintColor: Colors.white),
      ),
      navigatorKey: navigatorKey,
      home: const _Gate(),
    );
  }
}

class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (!s.ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return s.user == null ? const LoginScreen() : const Shell();
  }
}
