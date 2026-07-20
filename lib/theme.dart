import 'package:flutter/material.dart';

/// Zentrales Design-System der App "SBP Eye Settings".
/// Durchgehend dunkles, markantes Theme + ein paar wiederverwendbare Widgets,
/// damit alle Screens einheitlich aussehen.

// Markante Akzentfarbe (elektrisches Violett) + Kontrast-Cyan fuer Status "gut".
const Color kAccent      = Color(0xFF7C5CFF);
const Color kAccentGlow  = Color(0xFF9B8CFF);
const Color kGood        = Color(0xFF29E0A8);  // verbunden / autorisiert
const Color kWarn        = Color(0xFFFFB020);  // Achtung / nicht verbunden
const Color kBad         = Color(0xFFFF5C6C);  // Fehler / gesperrt

const Color kBg          = Color(0xFF0D0E13);  // App-Hintergrund (fast schwarz)
const Color kSurface     = Color(0xFF16181F);  // Karten
const Color kSurfaceHi   = Color(0xFF20232D);  // hervorgehobene Karten

ThemeData buildDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kAccent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: kAccent,
    surface: kSurface,
    surfaceContainerHighest: kSurfaceHi,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBg,
    canvasColor: kBg,
    splashColor: kAccent.withOpacity(.12),
    highlightColor: kAccent.withOpacity(.06),

    appBarTheme: const AppBarTheme(
      backgroundColor: kBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: .2,
        color: Colors.white,
      ),
    ),

    cardTheme: CardThemeData(
      color: kSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withOpacity(.06)),
      ),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF111219),
      surfaceTintColor: Colors.transparent,
      indicatorColor: kAccent.withOpacity(.22),
      elevation: 0,
      height: 66,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? kAccentGlow : Colors.white70,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? kAccentGlow : Colors.white60,
          )),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kAccent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: kAccentGlow),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: kSurfaceHi,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: kSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kBg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withOpacity(.10)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withOpacity(.10)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kAccent, width: 2),
      ),
    ),
  );
}

/// Kleiner, dezenter Abschnitts-Titel ueber Karten-Gruppen.
class SectionHeader extends StatelessWidget {
  final String label;
  final IconData? icon;
  const SectionHeader(this.label, {super.key, this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: Colors.white38),
            const SizedBox(width: 8),
          ],
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: Colors.white38,
            ),
          ),
        ],
      ),
    );
  }
}

/// Farbige Status-"Pille" (z. B. Verbunden / Gesperrt).
class StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const StatusPill(this.text, {super.key, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.15),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withOpacity(.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
          ],
          Text(text,
              style: TextStyle(
                  color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Signalstaerke als 4 Balken, aus RSSI (dBm) abgeleitet.
class SignalBars extends StatelessWidget {
  final int rssi;
  const SignalBars(this.rssi, {super.key});

  int get _level {
    if (rssi >= -60) return 4;
    if (rssi >= -70) return 3;
    if (rssi >= -80) return 2;
    if (rssi >= -90) return 1;
    return 0;
  }

  Color get _color {
    final l = _level;
    if (l >= 3) return kGood;
    if (l == 2) return kWarn;
    return kBad;
  }

  @override
  Widget build(BuildContext context) {
    final lvl = _level;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final on = i < lvl;
        return Container(
          width: 4,
          height: 7.0 + i * 4,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(
            color: on ? _color : Colors.white.withOpacity(.14),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}
