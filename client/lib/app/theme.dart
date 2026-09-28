import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';

// ── Colour tokens ─────────────────────────────────────────────────────────────

/// **Deprecated as the app-wide default — kept as a reference/compatibility
/// palette only.**
///
/// Hidden Eleven's single design system is now Night Tactics
/// (`HETheme`'s `pf*` tokens, `he_theme.dart`) — violet primary, magenta as
/// the one reserved "hot" accent, gold reserved for hidden/classified/reveal
/// moments. `buildAppTheme()` below sources every `ThemeData` default from
/// those tokens, not from this class.
///
/// This class remains fully defined, unchanged, because ~40+ call sites on
/// not-yet-migrated screens (Home, Host Room, Join Room, Lobby, Results,
/// Settings, and other screens outside this batch's approved file list)
/// still reference it directly, bypassing the theme entirely via explicit
/// `Scaffold(backgroundColor: HEColors....)` and similar. Deleting or
/// `@Deprecated`-annotating individual members now would either break those
/// screens or blanket the analyzer in warnings for code this batch is not
/// touching. It is retired in place, screen by screen, across Phases 2–3;
/// only once nothing references it does it get deleted.
class HEColors {
  HEColors._();

  // Background layers — darkest → most elevated
  static const background = Color(0xFF070C18);
  static const surface = Color(0xFF0F1826);
  static const surfaceElevated = Color(0xFF182236);
  static const surfaceHigh = Color(0xFF1F2E48); // modals / sheet headers

  // Primary accent — emerald
  static const accent = Color(0xFF00CC74);
  static const accentMuted = Color(0xFF007542);
  static const accentDim = Color(0xFF003A20); // very muted accent bg
  static const onAccent = Color(0xFF000E07);

  // Gold — wins, rewards, top picks ONLY
  static const gold = Color(0xFFFFD95A);
  static const goldDim = Color(0xFF7A5C00);
  static const onGold = Color(0xFF1A1200);

  // ── Brand palette — derived from the Hidden Eleven crest logo ──────────────
  // The logo is a deep-navy shield with a bright cyan pitch diagram. This is
  // the start of the wider Hidden Eleven visual identity, applied first on
  // the Home page. `accent` (emerald) remains the established in-game accent
  // on other screens for now — migrating them is separate, future work.
  // `gold` above doubles as this palette's deliberate warm complementary
  // accent (trophy/premium energy against the cool navy + cyan pairing) —
  // already used for tournament/result "winner" moments, so reusing it here
  // keeps the whole app's premium/CTA language consistent.
  static const brandNavy = Color(0xFF0B1E3D); // logo shield navy
  static const brandNavyDeep = Color(0xFF050D1C); // darkest navy, hero backdrop
  static const brandCyan = Color(0xFF2FAEE0); // logo pitch-line cyan
  static const brandCyanDim = Color(0xFF0F3A52); // muted cyan surface tint
  static const onBrandCyan = Color(0xFF00131C);

  // Text
  static const textPrimary = Color(0xFFF0F5FF);
  static const textSecondary = Color(0xFF7C8FA8);
  static const textMuted = Color(0xFF485A72);

  // Borders / separators
  static const inputBorder = Color(0xFF243455);
  static const inputBorderFocused = accent;
  static const divider = Color(0xFF1A2B42);

  // Semantic
  static const error = Color(0xFFE55353);
  static const info = Color(0xFF4A9EE8);
  static const warning = Color(0xFFF0A500);

  // Player avatar palette — 8 distinct hues, cycled by name
  static const List<Color> _avatarPalette = [
    Color(0xFF3A7BD5),
    Color(0xFF9B59B6),
    Color(0xFF00CC74),
    Color(0xFFE67E22),
    Color(0xFFE91E63),
    Color(0xFF1ABC9C),
    Color(0xFFF39C12),
    Color(0xFF5B8DEF),
  ];

  static Color avatarColor(String name) {
    if (name.isEmpty) return _avatarPalette[0];
    return _avatarPalette[name.codeUnitAt(0) % _avatarPalette.length];
  }
}

// ── Spacing rhythm (8 px base) ────────────────────────────────────────────────

class HESpacing {
  HESpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;
}

// ── Border radii ──────────────────────────────────────────────────────────────

class HERadius {
  HERadius._();
  static const double xs = 6;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;

  static BorderRadius circular(double r) => BorderRadius.circular(r);
  static final BorderRadius cardSm = BorderRadius.circular(sm);
  static final BorderRadius cardMd = BorderRadius.circular(md);
  static final BorderRadius cardLg = BorderRadius.circular(lg);
  static final BorderRadius cardXl = BorderRadius.circular(xl);
}

// ── Reusable shadows ──────────────────────────────────────────────────────────

class HEShadows {
  HEShadows._();

  static List<BoxShadow> get sm => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.28),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get md => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.36),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get lg => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.45),
      blurRadius: 32,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> accent({double intensity = 0.18}) => [
    BoxShadow(
      color: HEColors.accent.withValues(alpha: intensity),
      blurRadius: 20,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> gold({double intensity = 0.25}) => [
    BoxShadow(
      color: HEColors.gold.withValues(alpha: intensity),
      blurRadius: 20,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> cyan({double intensity = 0.25, double blur = 28}) => [
    BoxShadow(
      color: HEColors.brandCyan.withValues(alpha: intensity),
      blurRadius: blur,
      spreadRadius: 2,
    ),
  ];
}

// ── Shared text style helpers ─────────────────────────────────────────────────

class HETextStyles {
  HETextStyles._();

  /// ALL-CAPS micro section label (PLAYERS, ROUND, etc.)
  static const label = TextStyle(
    color: HETheme.pfTextSecondary,
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.4,
    height: 1.0,
  );

  static const labelAccent = TextStyle(
    color: HETheme.pfAccentViolet,
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.4,
    height: 1.0,
  );
}

// ── Theme — Night Tactics, the single app-wide design system ─────────────────
//
// Every default below sources from `HETheme`'s `pf*` tokens (violet primary,
// magenta reserved as the one "hot" accent, gold reserved for hidden/
// classified/reveal moments) instead of the legacy `HEColors` above. This is
// what makes every stock Material widget that doesn't style itself — every
// un-customized `AlertDialog`, `SnackBar`, `PopupMenuButton`, default
// `TextField` — resolve onto the same system as the rest of the app, in one
// place, rather than each screen needing its own opt-in.
//
// Radii and spacing are left at their existing literal values (12, 20, etc.)
// — this pass retires colour tokens, not geometry; changing the shape
// language app-wide is a separate, later decision.

TextTheme _buildTextTheme() {
  final base = GoogleFonts.interTextTheme();
  return base.copyWith(
    displayLarge: base.displayLarge?.copyWith(
      color: HETheme.pfTextPrimary,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    ),
    displayMedium: base.displayMedium?.copyWith(
      color: HETheme.pfTextPrimary,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    ),
    headlineLarge: base.headlineLarge?.copyWith(
      color: HETheme.pfTextPrimary,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
    ),
    headlineMedium: base.headlineMedium?.copyWith(
      color: HETheme.pfTextPrimary,
      fontWeight: FontWeight.w600,
    ),
    titleLarge: base.titleLarge?.copyWith(
      color: HETheme.pfTextPrimary,
      fontWeight: FontWeight.w600,
    ),
    titleMedium: base.titleMedium?.copyWith(
      color: HETheme.pfTextPrimary,
      fontWeight: FontWeight.w500,
    ),
    bodyLarge: base.bodyLarge?.copyWith(color: HETheme.pfTextPrimary),
    bodyMedium: base.bodyMedium?.copyWith(color: HETheme.pfTextSecondary),
    labelLarge: base.labelLarge?.copyWith(
      color: HETheme.pfTextPrimary,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    ),
  );
}

ThemeData buildAppTheme() {
  final textTheme = _buildTextTheme();

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: HETheme.pfBgVoid,
    colorScheme: const ColorScheme.dark(
      surface: HETheme.pfSurfaceRaised,
      primary: HETheme.pfAccentViolet,
      onPrimary: HETheme.pfTextPrimary,
      secondary: HETheme.pfSecondaryViolet,
      error: HETheme.pfDanger,
      onSurface: HETheme.pfTextPrimary,
    ),
    textTheme: textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: HETheme.pfSurfaceDeep,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        color: HETheme.pfTextPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        fontFamily: 'Inter',
      ),
      iconTheme: IconThemeData(color: HETheme.pfTextSecondary, size: 20),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: HETheme.pfSurfaceRaised,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: HETheme.pfBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: HETheme.pfBorder),
      ),
      // The one field-level "hot" moment — a visible magenta focus ring,
      // matching the convention already established on the First Touch
      // Experience screens' text fields, now centralised here instead of
      // duplicated per-widget.
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: HETheme.pfAccentMagenta, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: HETheme.pfDanger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: HETheme.pfDanger, width: 2),
      ),
      hintStyle: const TextStyle(color: HETheme.pfTextMuted),
      labelStyle: const TextStyle(color: HETheme.pfTextSecondary),
    ),
    // Disabled violet is deliberately still violet (a dimmer, desaturated
    // step via pfSecondaryViolet) rather than falling back to grey or gold —
    // gold stays reserved for hidden/classified/reveal moments and must
    // never read as "the default action colour."
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: HETheme.pfAccentViolet,
        foregroundColor: HETheme.pfTextPrimary,
        disabledBackgroundColor: HETheme.pfSecondaryViolet.withValues(
          alpha: 0.45,
        ),
        disabledForegroundColor: HETheme.pfTextPrimary.withValues(alpha: 0.5),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          letterSpacing: 0.3,
        ),
        elevation: 0,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: HETheme.pfAccentViolet,
        foregroundColor: HETheme.pfTextPrimary,
        disabledBackgroundColor: HETheme.pfSecondaryViolet.withValues(
          alpha: 0.45,
        ),
        disabledForegroundColor: HETheme.pfTextPrimary.withValues(alpha: 0.5),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          letterSpacing: 0.3,
        ),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: HETheme.pfTextPrimary,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: HETheme.pfBorder, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          letterSpacing: 0.2,
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(color: HETheme.pfBorder, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: HETheme.pfSurfaceGlass,
      contentTextStyle: const TextStyle(
        color: HETheme.pfTextPrimary,
        fontSize: 14,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HEShape.rMd),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    // Repointing this one theme fixes every un-styled Lobby AlertDialog
    // (join-request, kick, connection-lost, insufficient-pool) at once —
    // they render through this default, they never style themselves.
    dialogTheme: DialogThemeData(
      backgroundColor: HETheme.pfSurfaceRaised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: const TextStyle(
        color: HETheme.pfTextPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        fontFamily: 'Inter',
      ),
      contentTextStyle: const TextStyle(
        color: HETheme.pfTextSecondary,
        fontSize: 14,
        fontFamily: 'Inter',
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: HETheme.pfSurfaceGlass,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(color: HETheme.pfTextPrimary, fontSize: 14),
    ),
  );
}
