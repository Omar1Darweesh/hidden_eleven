import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for Hidden Eleven's UI.
///
/// **The single live system is the `pf*` ("Purple Floodlights" / Night
/// Tactics) block further down this file** — violet primary, magenta as the
/// one reserved "hot" accent, gold reserved for hidden/classified/reveal
/// moments. `theme.dart`'s `buildAppTheme()` sources every app-wide default
/// from it, and all new player-facing UI should too.
///
/// The surfaces/accents immediately below ("Matchday Intelligence" — cyan
/// primary) are **deprecated**: kept, unchanged, only because a number of
/// not-yet-migrated screens (Home, Host Room, Join Room, Lobby, and their
/// shared widgets outside this batch) still read them directly. They are
/// retired screen by screen across later phases and deleted once nothing
/// references them — do not build new UI against this block.
class HETheme {
  HETheme._();

  // ── Surfaces (deprecated — see class doc comment) ──────────────────────
  static const bg = Color(0xFF070B12);
  static const surface = Color(0xFF0F1826);
  static const surfaceRaised = Color(0xFF16223A);
  static const border = Color(0xFF223049);

  /// Deep hero-panel navy — darker than [surface], lighter than [bg]. For the
  /// large branded panels on the first-touch screens (Home/Host/Join/Lobby
  /// hero headers, room-code hero) that need to read as "recessed into the
  /// room" rather than sitting flush with ordinary content surfaces. The one
  /// token this migration batch adds to HETheme — see he_theme.dart's own
  /// doc comment: everything else these screens need already existed here.
  static const surfaceDeep = Color(0xFF0A1220);

  // ── Accents (deprecated) — each meaning-locked, never reused ────────────
  /// Interaction / active-turn / primary CTA.
  static const accentCyan = Color(0xFF35D6E8);

  /// Hidden picks, reveal moments, premium card tier. Reserved.
  static const accentGold = Color(0xFFE8B84B);

  /// Confirmed chemistry, success states, connected status.
  static const accentEmerald = Color(0xFF3FDB8F);

  /// Timer-critical, destructive confirm, disconnected status. Urgency only.
  static const danger = Color(0xFFF0654E);

  /// Chemistry "league" link type only — never used elsewhere. Superseded by
  /// [chemLeague] (amber) under the Purple Floodlights palette, where this
  /// exact hex would collide with [accentViolet] — kept defined, unused, so
  /// nothing that still reads it (there is nothing left, but future-proof)
  /// silently breaks.
  static const linkLeague = Color(0xFF8C6BFF);

  // ── Text ─────────────────────────────────────────────────────────────────
  static const textPrimary = Color(0xFFEAF0FA);
  static const textSecondary = Color(0xFF9FB0C8);
  static const textMuted = Color(0xFF64758F);

  // ═══════════════════════════════════════════════════════════════════════
  // ── Purple Floodlights ───────────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════
  //
  // A second, additive art-direction layer on top of the Matchday
  // Intelligence tokens above — same non-destructive pattern this class
  // already uses over `HEColors`. "A tactical football game played under
  // neon stadium floodlights at night": deep near-black plum surfaces,
  // violet as the primary interactive color, magenta reserved for the rare
  // "hot" moment (focus, active/live, just-became-ready).
  //
  // Scope: applied only where a widget explicitly opts in via
  // `HEVisualStyle.purpleFloodlights` (see `he_visual_style.dart`) — the
  // First Touch Experience screens (Home, Host Room, Join Room, Lobby) and
  // their resume cards. Every other screen keeps reading the tokens above
  // completely unchanged. This block exists so that a later, deliberate
  // gameplay migration (CommandStrip, TimerRing, SealedDossierCard,
  // ChemistryLinkPainter, results) has one real palette to migrate onto
  // instead of two competing systems.

  // ── Purple surfaces — near-black plum, deliberately desaturated so the
  // violet/magenta accents below are what actually reads as "lit" ─────────
  /// App background / night void.
  static const pfBgVoid = Color(0xFF0A0714);

  /// Deep surface — hero panels, room-code hero, brand headers.
  static const pfSurfaceDeep = Color(0xFF120D22);

  /// Raised surface — ordinary cards, section cards.
  static const pfSurfaceRaised = Color(0xFF1C1530);

  /// Glass/overlay surface — dialogs, bottom sheets. Use with ~0.55 alpha
  /// over the background, not as an opaque fill.
  static const pfSurfaceGlass = Color(0xFF2A1F45);

  /// Border/divider on purple surfaces.
  static const pfBorder = Color(0xFF352A52);

  // ── Purple accents — each meaning-locked ─────────────────────────────────
  /// Primary interactive color — CTAs, active states, links, primary focus.
  /// Chosen over magenta as the *sustained* primary because it holds up at
  /// body/label sizes without the mild vibration effect magenta shows at
  /// the same saturation over large or textual areas (see he_theme.dart's
  /// Phase A audit). Reserve magenta ([pfAccentMagenta]) for the rarer,
  /// hotter moment instead.
  static const pfAccentViolet = Color(0xFF8B5CF6);

  /// Brighter violet used ONLY in glow/BoxShadow/gradient falloff — never as
  /// a solid fill or text color.
  static const pfAccentVioletGlow = Color(0xFFA78BFA);

  /// The one "hot" accent in the whole system — focus rings, the active/live
  /// indicator, a just-became-ready state, room-code copy/paste success
  /// flash. Deliberately rare: if more than one thing on screen is magenta
  /// at once, something has gone off-brief.
  static const pfAccentMagenta = Color(0xFFE930C7);

  /// Secondary violet — secondary button borders, inactive-but-selectable
  /// chip borders. Quieter than [pfAccentViolet], never used for CTAs.
  static const pfSecondaryViolet = Color(0xFF6D4AAE);

  /// Soft lavender text/accent — eyebrow labels, decorative captions. Not a
  /// body-text color (see [pfTextSecondary] for that).
  static const pfLavenderText = Color(0xFFC9B8F5);

  // ── Purple semantic colors — kept OUT of the violet/magenta family on
  // purpose, so they stay legible as distinct meanings, not more brand ────
  /// Success / ready / connected / chemistry-satisfied. Identical intent to
  /// [accentEmerald] — restated here so Purple Floodlights surfaces never
  /// need to reach back into the Matchday Intelligence block for it.
  static const pfSuccess = Color(0xFF34D399);

  /// Warning — new; the Matchday Intelligence block never needed its own.
  static const pfWarning = Color(0xFFF5A524);

  /// Danger / destructive / disconnected. Same role as [danger] — restated
  /// for the same reason as [pfSuccess].
  static const pfDanger = Color(0xFFF0654E);

  /// Hidden Picks / Sealed Dossier / classified / reveal-adjacent meaning.
  /// Deliberately identical to [accentGold] — gold already sits outside the
  /// violet/magenta hue family, so it stays maximally distinct from the new
  /// primary without needing a new value. Never reuse [pfAccentViolet] or
  /// [pfAccentMagenta] for this meaning, even though both are technically
  /// "premium-looking" — gold is what actually signals "hidden/classified"
  /// throughout the app today.
  static const pfGold = Color(0xFFE8B84B);

  /// Bronze rank/achievement tier (3rd place). Sits outside the violet/
  /// magenta/gold family so all four rank tiers ([pfGold], [pfLavenderText]
  /// for silver/neutral, this, and plain [pfTextSecondary] for 4th+) stay
  /// visually distinct from each other and from generic containers.
  static const pfBronze = Color(0xFFC2793D);

  // ── Position-group identity tags (subs panel) ────────────────────────────
  // Category labels ("ATT"/"MID"/"DEF"/"extra"), never a game state — kept
  // deliberately outside the pfGold/pfDanger/pfSuccess family so a position
  // tag is never mistaken for an error, achievement, or success signal.
  static const pfPositionAttack = Color(0xFFE0708A);
  static const pfPositionMid = Color(0xFFD9A857);
  static const pfPositionDef = Color(0xFF6FA8DC);
  static const pfPositionExtra = Color(0xFF8B7FD6);

  // ── Chemistry-link colors (Purple Floodlights palette) ──────────────────
  // Club and Nationality are UNCHANGED from the Matchday Intelligence
  // block — cyan and emerald both already sit outside the violet/magenta
  // family, so they stay maximally distinct from the new primary color
  // without any change. League moves off violet (which would now collide
  // with [pfAccentViolet]) onto amber instead. Line PATTERN (solid/dashed/
  // dotted) remains the primary distinguishing signal regardless of color —
  // this is a color-constant change only, `ChemistryLinkPainter`'s
  // computation, privacy rules, and no-scoring-effect guarantee are
  // untouched.
  /// Chemistry link — Club. Same value as [accentCyan].
  static const chemClub = accentCyan;

  /// Chemistry link — Nationality. Same value as [accentEmerald].
  static const chemNationality = accentEmerald;

  /// Chemistry link — League. Amber, replacing the old violet [linkLeague]
  /// specifically because violet is now the primary UI accent.
  static const chemLeague = Color(0xFFF0A64C);

  // ═══════════════════════════════════════════════════════════════════════
  // ── Night Tactics — arena & pitch ────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════
  //
  // The gameplay-screen extension of Purple Floodlights. Everything above is
  // chrome; these are the tokens for the one big object on the game screen —
  // the pitch, and the lit frame it sits in.
  //
  // Design note on why the turf is still green: a fully violet pitch stops
  // reading as football. Instead the grass keeps its own (cooler, deeper)
  // green and [arenaLightWash] composites the *same* violet floodlight over
  // it that lights the background — so the pitch is integrated with the arena
  // by shared lighting rather than by shared hue.

  /// The pitch frame's rim. One step brighter than [pfBorder] — the arena is
  /// the only object in the app allowed to outrank ordinary panel borders.
  static const arenaRim = Color(0xFF3D2E63);

  /// Turf shadow stripe. Cooler and deeper than the legacy `#0C2516`.
  static const pitchTurfDeep = Color(0xFF0C2A22);

  /// Turf lit stripe. Paired with [pitchTurfDeep] as soft gradient bands
  /// rather than the hard-edged rectangles the old painter drew.
  static const pitchTurfLit = Color(0xFF123A2C);

  /// Field markings — a slightly warm white, so chalk reads as chalk under a
  /// violet light rather than going blue.
  static const pitchLine = Color(0xFFD9F2E8);

  /// The integration trick: a top-down violet radial composited over the
  /// turf at low alpha. Use via `withValues(alpha: …)` — never as an opaque
  /// fill.
  static const arenaLightWash = pfAccentViolet;

  // ── Purple text ───────────────────────────────────────────────────────────
  static const pfTextPrimary = Color(0xFFF5F2FB);
  static const pfTextSecondary = Color(0xFFA79BC4);
  static const pfTextMuted = Color(0xFF6E6389);

  // ── Spacing (8px rhythm — same scale as HESpacing, restated for the
  // widgets in this system so they don't need to import both files for
  // every value) ───────────────────────────────────────────────────────────
  static const spaceXs = 4.0;
  static const spaceSm = 8.0;
  static const spaceMd = 12.0;
  static const spaceLg = 16.0;
  static const spaceXl = 24.0;
  static const spaceXxl = 32.0;

  // ── Radius ───────────────────────────────────────────────────────────────
  static const radiusSm = 8.0;
  static const radiusMd = 12.0;
  static const radiusLg = 16.0;
  static const radiusPill = 999.0;

  // ── Breakpoints ──────────────────────────────────────────────────────────
  static const breakpointMobile = 700.0;
  static const breakpointTablet = 1080.0;

  // ── Typography ───────────────────────────────────────────────────────────
  // Display: condensed, heavy, stadium-signage character. Uppercase by
  // convention wherever it's used — see [displayLabel].
  //
  // NOTE: the dossier names "Big Shoulders Display" — the installed
  // google_fonts (^8.1.0) generates this Google Fonts family as a single
  // variable-weight face, `GoogleFonts.bigShoulders`, not a separate
  // `...Display` method (Google merged the Display/Text cuts upstream).
  // The weight axis below reproduces the same intended contrast.
  static TextStyle display({
    double size = 28,
    FontWeight weight = FontWeight.w800,
    Color color = textPrimary,
    double letterSpacing = -0.2,
  }) => GoogleFonts.bigShoulders(
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
    height: 0.95,
  );

  /// Uppercase eyebrow/label variant of [display] — screen titles, phase
  /// names, stamps ("MATCHDAY", "FULL-TIME").
  static TextStyle displayLabel({
    double size = 13,
    Color color = textSecondary,
    double letterSpacing = 1.4,
  }) => GoogleFonts.bigShoulders(
    fontSize: size,
    fontWeight: FontWeight.w700,
    color: color,
    letterSpacing: letterSpacing,
  );

  /// Body copy — sentence case, all readable content. Reuses the existing
  /// Inter body face already loaded app-wide rather than adding a second
  /// body font, which the dossier's own principle ("don't over-theme") argues
  /// against introducing without a concrete reason.
  static TextStyle body({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color color = textSecondary,
  }) => GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color);

  /// Tabular-numeral mono — scores, timers, room codes, ratings. Anything
  /// that must align in a column or count down without jitter.
  static TextStyle mono({
    double size = 13,
    FontWeight weight = FontWeight.w600,
    Color color = textPrimary,
  }) => GoogleFonts.ibmPlexMono(
    fontSize: size,
    fontWeight: weight,
    color: color,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}
