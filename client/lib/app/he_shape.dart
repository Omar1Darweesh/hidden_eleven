import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';

/// "Night Tactics" shape system — the radius scale and elevation model that
/// replaces the game screen's reliance on thin bordered rectangles.
///
/// Additive, like [HETheme] itself: `HERadius`/`HEShadows` in `theme.dart`
/// stay exactly as they are and every screen that reads them is unaffected.
/// Only surfaces that have deliberately opted into Night Tactics read from
/// here.
///
/// The core idea this encodes: a surface's *meaning* is carried by its
/// elevation level, not by an ad-hoc combination of fill and border chosen
/// per call site. There are four levels and each one is a complete triple of
/// (fill, border, shadow) — never mix and match pieces of two levels.
class HEShape {
  HEShape._();

  // ── Radius scale ─────────────────────────────────────────────────────────
  /// Chips, phase labels, tab items, status bubbles, the match bar, CTAs.
  static const double rPill = 999;

  /// Badges, inline tags, progress tracks.
  static const double rSm = 10;

  /// Player cards on the pitch, bench rows, list items.
  static const double rMd = 16;

  /// Secondary panels, dialogs, drawers.
  static const double rLg = 22;

  /// Mission card, action drawer, primary floating panels.
  static const double rXl = 28;

  /// The pitch arena frame — the single largest radius in the app.
  static const double rArena = 32;

  /// The mission card's one clipped corner. Deliberately used **once per
  /// screen** so it stays a signature rather than becoming a mannerism —
  /// if a second surface wants this, it wants [rXl] instead.
  static const BorderRadius signature = BorderRadius.only(
    topLeft: Radius.circular(rXl),
    topRight: Radius.circular(rXl),
    bottomLeft: Radius.circular(rXl),
    bottomRight: Radius.circular(rSm),
  );

  static BorderRadius get pill => BorderRadius.circular(rPill);
  static BorderRadius get sm => BorderRadius.circular(rSm);
  static BorderRadius get md => BorderRadius.circular(rMd);
  static BorderRadius get lg => BorderRadius.circular(rLg);
  static BorderRadius get xl => BorderRadius.circular(rXl);
  static BorderRadius get arena => BorderRadius.circular(rArena);
}

/// The four elevation levels. Each returns a complete [BoxDecoration] so a
/// call site can't accidentally take one level's fill with another's border.
///
/// * [e1] — passive information. Matte, recessive, no glow.
/// * [e2] — floating panels and drawers. Glass gradient, rim border, real
///   drop shadow so the panel reads as an *object with air around it*.
/// * [e3] — the one thing the player must act on. e2 plus a violet wash, a
///   magenta rim, and an outer glow.
///
/// There is no `e0`: the ground is the arena background itself, which is not
/// a decorated box.
class HEElevation {
  HEElevation._();

  /// Passive information — squad preview, scoring summary, inactive states.
  static BoxDecoration e1({BorderRadius? radius, Color? borderColor}) =>
      BoxDecoration(
        color: HETheme.pfSurfaceRaised.withValues(alpha: 0.72),
        borderRadius: radius ?? HEShape.lg,
        border: Border.all(color: borderColor ?? HETheme.pfBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      );

  /// Floating panels and drawers. The 168° gradient (rather than a flat fill)
  /// is what makes these read as lit objects rather than grey boxes.
  static BoxDecoration e2({BorderRadius? radius, Color? borderColor}) =>
      BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HETheme.pfSurfaceGlass.withValues(alpha: 0.62),
            HETheme.pfSurfaceRaised.withValues(alpha: 0.50),
          ],
        ),
        borderRadius: radius ?? HEShape.xl,
        border: Border.all(color: borderColor ?? HETheme.arenaRim),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.42),
            blurRadius: 32,
            offset: const Offset(0, 10),
          ),
        ],
      );

  /// The active task. Exactly one surface on screen may be at this level —
  /// see the "one hot thing" rule in the Night Tactics direction.
  static BoxDecoration e3({BorderRadius? radius, double glow = 1.0}) =>
      BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              HETheme.pfAccentViolet.withValues(alpha: 0.10),
              HETheme.pfSurfaceGlass.withValues(alpha: 0.68),
            ),
            HETheme.pfSurfaceRaised.withValues(alpha: 0.58),
          ],
        ),
        borderRadius: radius ?? HEShape.signature,
        border: Border.all(
          color: HETheme.pfAccentMagenta.withValues(alpha: 0.45),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.42),
            blurRadius: 32,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: HETheme.pfAccentMagenta.withValues(alpha: 0.50 * glow),
            blurRadius: 44,
            spreadRadius: -14,
          ),
        ],
      );
}
