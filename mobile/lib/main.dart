import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
    final scheme = ColorScheme.fromSeed(seedColor: brand).copyWith(primary: brand, onPrimary: Colors.white, surface: Colors.white);
    return MaterialApp(
      title: 'ParkSpace',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        textTheme: GoogleFonts.plusJakartaSansTextTheme(ThemeData.light().textTheme),
        scaffoldBackgroundColor: const Color(0xFFF5F6FB),
        splashFactory: InkSparkle.splashFactory,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white, surfaceTintColor: Colors.white, elevation: 0, scrolledUnderElevation: 0.5,
          titleTextStyle: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF14171F)),
        ),
        cardTheme: CardThemeData(
          color: Colors.white, elevation: 2, shadowColor: const Color(0x1A1B2559), margin: EdgeInsets.zero, surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        chipTheme: ChipThemeData(
          shape: const StadiumBorder(side: BorderSide(color: Color(0xFFE3E6F0))),
          backgroundColor: Colors.white, selectedColor: const Color(0xFFDDE6FF), checkmarkColor: brand,
          labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600),
          side: const BorderSide(color: Color(0xFFE3E6F0)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: const Color(0xFFF8F9FD),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE3E6F0))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE3E6F0))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: brand, width: 1.6)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 50), elevation: 0,
            textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 50), side: const BorderSide(color: Color(0xFFD5DAEA)),
            textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), surfaceTintColor: Colors.white),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white, surfaceTintColor: Colors.white, showDragHandle: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        ),
        snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white, surfaceTintColor: Colors.white, indicatorColor: const Color(0xFFDDE6FF), height: 68,
          labelTextStyle: WidgetStatePropertyAll(GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        navigationRailTheme: const NavigationRailThemeData(indicatorColor: Color(0xFFDDE6FF), backgroundColor: Colors.white),
        dividerTheme: const DividerThemeData(color: Color(0xFFEDEFF6)),
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
