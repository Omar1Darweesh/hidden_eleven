import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:hidden_eleven/app/config.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/models/chemistry_bonus.dart';
import 'package:hidden_eleven/features/game/services/chemistry_evaluator.dart';
import 'package:hidden_eleven/features/game/widgets/fit_note_card.dart';
import 'package:hidden_eleven/shared/data/asset_fallbacks.dart';
import 'package:hidden_eleven/shared/widgets/jersey_back.dart';

// ── Rating-tier colour palette (single source of truth) ──────────────────────

class CardTier {
  const CardTier({
    required this.gradientTop,
    required this.gradientBottom,
    required this.accentColor,
    required this.borderColor,
    required this.imageOverlay,
    this.isPremium = false,
  });

  final Color gradientTop;
  final Color gradientBottom;
  final Color accentColor;
  final Color borderColor;
  final Color imageOverlay;

  /// Gold/Icon/Hero bands only. Gates the animated foil sweep on
  /// [PlayerCard] — a shimmer on every card would just be noise; keeping it
  /// to the top tiers is what makes it read as special when it appears.
  final bool isPremium;

  // Admin-configured rating→colour bands (sorted DESC by minRating). Null until
  // loaded; falls back to the built-in tiers below.
  static List<({int minRating, Color color})>? _configured;

  /// Fetches the admin card-tier config once. Safe to call repeatedly.
  static Future<void> ensureLoaded() async {
    if (_configured != null) return;
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.httpBase}/api/admin/card-tiers'),
        headers: {'ngrok-skip-browser-warning': 'true'},
      );
      if (res.statusCode >= 300) return;
      final data = jsonDecode(res.body) as List<dynamic>;
      final tiers =
          data
              .map(
                (e) => (
                  minRating: (e['minRating'] as num).toInt(),
                  color: _parseHex(e['color'] as String?),
                ),
              )
              .toList()
            ..sort((a, b) => b.minRating.compareTo(a.minRating));
      if (tiers.isNotEmpty) _configured = tiers;
    } catch (_) {
      // keep built-in defaults
    }
  }

  static Color _parseHex(String? hex) {
    if (hex == null) return const Color(0xFFB0BDD8);
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    return Color(int.tryParse(h, radix: 16) ?? 0xFFB0BDD8);
  }

  /// Builds a full tier (gradient + accents) from a single base colour, so the
  /// admin only needs to pick one colour per rating band.
  static CardTier _fromBaseColor(Color base) {
    return CardTier(
      gradientTop: Color.lerp(base, Colors.black, 0.62)!,
      gradientBottom: Color.lerp(base, Colors.black, 0.82)!,
      accentColor: base,
      borderColor: base,
      imageOverlay: base,
    );
  }

  /// Special frames that override the normal rating-tier band entirely —
  /// admin-assigned per club via [AdminClub.cardStyle] (Clubs tab "Card
  /// Style" picker), matching real FIFA/FC's Icon (gold/brown) and Hero
  /// (blue/purple) card treatments.
  static const Map<String, CardTier> _specialStyles = {
    'icon': CardTier(
      gradientTop: Color(0xFF6B4A00),
      gradientBottom: Color(0xFF2E1D00),
      accentColor: Color(0xFFF2C879),
      borderColor: Color(0xFFF2C879),
      imageOverlay: Color(0xFFF2C879),
      isPremium: true,
    ),
    'hero': CardTier(
      gradientTop: Color(0xFF3A1660),
      gradientBottom: Color(0xFF160A33),
      accentColor: Color(0xFF9B6BFF),
      borderColor: Color(0xFF9B6BFF),
      imageOverlay: Color(0xFF9B6BFF),
      isPremium: true,
    ),
  };

  /// Resolves a card's frame: [cardStyle] (from the card's club — 'icon' /
  /// 'hero') wins outright when set and recognized; otherwise falls back to
  /// the normal rating-tier band via [forRating].
  static CardTier forCard(int rating, String? cardStyle) {
    if (cardStyle != null && _specialStyles.containsKey(cardStyle)) {
      return _specialStyles[cardStyle]!;
    }
    return forRating(rating);
  }

  static CardTier forRating(int rating) {
    final cfg = _configured;
    if (cfg != null) {
      for (final t in cfg) {
        if (rating >= t.minRating) return _fromBaseColor(t.color);
      }
      return _fromBaseColor(cfg.last.color);
    }
    if (rating >= 90) {
      return const CardTier(
        gradientTop: Color(0xFF7B5B00),
        gradientBottom: Color(0xFF3A2A00),
        accentColor: Color(0xFFFFD700),
        borderColor: Color(0xFFFFD700),
        imageOverlay: Color(0xFFFFD700),
        isPremium: true,
      );
    }
    if (rating >= 85) {
      return const CardTier(
        gradientTop: Color(0xFF5A4600),
        gradientBottom: Color(0xFF2C2200),
        accentColor: Color(0xFFEEC900),
        borderColor: Color(0xFFEEC900),
        imageOverlay: Color(0xFFEEC900),
        isPremium: true,
      );
    }
    if (rating >= 80) {
      return const CardTier(
        gradientTop: Color(0xFF1A4060),
        gradientBottom: Color(0xFF0A2035),
        accentColor: Color(0xFFB0C8E0),
        borderColor: Color(0xFF6090B8),
        imageOverlay: Color(0xFFB0C8E0),
      );
    }
    if (rating >= 75) {
      return const CardTier(
        gradientTop: Color(0xFF4A3418),
        gradientBottom: Color(0xFF241908),
        accentColor: Color(0xFFCD7F32),
        borderColor: Color(0xFFCD7F32),
        imageOverlay: Color(0xFFCD7F32),
      );
    }
    return const CardTier(
      gradientTop: Color(0xFF1E2A40),
      gradientBottom: Color(0xFF111824),
      accentColor: Color(0xFFB0BDD8),
      borderColor: Color(0xFF2A3A55),
      imageOverlay: Color(0xFF8090A8),
    );
  }
}

// ── Club logo widget ──────────────────────────────────────────────────────────

/// Renders a club logo image. Priority: [logoUrl] > name-based CDN lookup > initials.
/// Pass [logoUrl] from server data when available; falls back gracefully.
class CardLogoWidget extends StatelessWidget {
  const CardLogoWidget({
    super.key,
    required this.name,
    required this.size,
    this.logoUrl,
    this.accentColor,
  });

  final String name;
  final double size;
  final String? logoUrl;
  final Color? accentColor;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, min(2, name.length)).toUpperCase();
  }

  String? get _resolvedUrl => logoUrl ?? kClubLogoUrls[name];

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? HETheme.pfAccentViolet;
    final url = _resolvedUrl;
    if (url != null) {
      return SizedBox(
        width: size,
        height: size,
        // cacheWidth: cap decode resolution to the actual badge size — see
        // player_card.dart's _CardImage for why this matters (a subs-phase
        // spin can render several of these concurrently).
        child: Image.network(
          url,
          fit: BoxFit.contain,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
              .clamp(24.0, 200.0)
              .round(),
          errorBuilder: (context, error, stackTrace) => _initialsWidget(accent),
        ),
      );
    }
    return _initialsWidget(accent);
  }

  Widget _initialsWidget(Color accent) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 1),
      ),
      child: Center(
        child: Text(
          _initials,
          style: TextStyle(
            color: accent,
            fontSize: size * 0.36,
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

// ── Country flag widget ───────────────────────────────────────────────────────

/// Renders a country flag using flagcdn.com. Uses country names as keys
/// (e.g. "England", "Brazil") matching the server's nationality strings.
/// Pass [flagUrl] directly for a server-provided URL (future-ready).
class FlagWidget extends StatelessWidget {
  const FlagWidget({
    super.key,
    required this.nationality,
    required this.size,
    this.flagUrl,
  });

  final String nationality;
  final double size;
  final String? flagUrl;

  String? get _resolvedUrl {
    if (flagUrl != null) return flagUrl;
    final code = kNatToCode[nationality];
    if (code == null) return null;
    return 'https://flagcdn.com/w40/$code.png';
  }

  @override
  Widget build(BuildContext context) {
    final url = _resolvedUrl;
    if (url != null) {
      return SizedBox(
        width: size * 1.4,
        height: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            cacheWidth: (size * 1.4 * MediaQuery.devicePixelRatioOf(context))
                .clamp(24.0, 200.0)
                .round(),
            errorBuilder: (context, error, stackTrace) => _fallback(),
          ),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return Icon(Icons.flag_rounded, size: size, color: HETheme.pfTextSecondary);
  }
}

// ── Player details modal ──────────────────────────────────────────────────────

/// Opens a centered player details dialog.
/// [onPick] — provide only for selection cards; omit for formation cards.
void showCardDetailsModal(
  BuildContext context, {
  required String playerName,
  required int rating,
  required String position,
  String? imageSeed,
  String? club,
  String? clubLogoUrl,
  String? primaryColor,
  String? secondaryColor,
  String? tertiaryColor,
  String? kitPattern,
  String? cardStyle,
  int? kitNumber,
  String? nationality,
  List<String> altPositions = const [],
  int pace = 0,
  int shooting = 0,
  int passing = 0,
  int dribbling = 0,
  int defending = 0,
  int physical = 0,
  List<ChemistryBonus> chemistryBonuses = const [],
  List<LineupCard> lineup = const [],
  VoidCallback? onPick,
}) {
  showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    // The default Material dialog transition animates a Transform+Opacity
    // over this entire subtree (image, gradients, multiple BoxShadows) —
    // that's an offscreen "save layer" composite of a shadow/gradient-heavy
    // tree, the same class of GPU-compositing operation that has already
    // caused native hangs/crashes on this app's constrained Impeller/
    // OpenGLES emulator targets (see club_roulette_drum.dart's history).
    // Skipping the transition removes that compositing cost entirely.
    animationStyle: AnimationStyle.noAnimation,
    builder: (ctx) => _CardDetailsDialog(
      playerName: playerName,
      rating: rating,
      position: position,
      imageSeed: imageSeed,
      club: club,
      clubLogoUrl: clubLogoUrl,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
      tertiaryColor: tertiaryColor,
      kitPattern: kitPattern,
      cardStyle: cardStyle,
      kitNumber: kitNumber,
      nationality: nationality,
      altPositions: altPositions,
      pace: pace,
      shooting: shooting,
      passing: passing,
      dribbling: dribbling,
      defending: defending,
      physical: physical,
      chemistryBonuses: chemistryBonuses,
      lineup: lineup,
      onPick: onPick != null
          ? () {
              Navigator.of(ctx).pop();
              onPick();
            }
          : null,
    ),
  );
}

// ── Details dialog ────────────────────────────────────────────────────────────

class _CardDetailsDialog extends StatelessWidget {
  const _CardDetailsDialog({
    required this.playerName,
    required this.rating,
    required this.position,
    this.imageSeed,
    this.club,
    this.clubLogoUrl,
    this.primaryColor,
    this.secondaryColor,
    this.tertiaryColor,
    this.kitPattern,
    this.cardStyle,
    this.kitNumber,
    this.nationality,
    this.altPositions = const [],
    this.pace = 0,
    this.shooting = 0,
    this.passing = 0,
    this.dribbling = 0,
    this.defending = 0,
    this.physical = 0,
    this.chemistryBonuses = const [],
    this.lineup = const [],
    this.onPick,
  });

  final String playerName;
  final int rating;
  final String position;
  final String? imageSeed;
  final String? club;
  final String? clubLogoUrl;
  final String? primaryColor;
  final String? secondaryColor;
  final String? tertiaryColor;
  final String? kitPattern;
  final String? cardStyle;
  final int? kitNumber;
  final String? nationality;
  final List<String> altPositions;
  final int pace;
  final int shooting;
  final int passing;
  final int dribbling;
  final int defending;
  final int physical;
  final List<ChemistryBonus> chemistryBonuses;
  final List<LineupCard> lineup;
  final VoidCallback? onPick;

  bool get _hasStats => pace > 0 || shooting > 0 || passing > 0;

  @override
  Widget build(BuildContext context) {
    final tier = CardTier.forCard(rating, cardStyle);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 360,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: HETheme.pfSurfaceDeep,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: tier.borderColor.withValues(alpha: 0.55),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: tier.accentColor.withValues(alpha: 0.20),
                blurRadius: 40,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Hero image ────────────────────────────────────────────
              _HeroImage(
                playerName: playerName,
                club: club,
                primaryColorHex: primaryColor,
                secondaryColorHex: secondaryColor,
                tertiaryColorHex: tertiaryColor,
                kitPattern: kitPatternFromName(kitPattern),
                numberSeed: imageSeed,
                kitNumber: kitNumber,
                tier: tier,
                rating: rating,
                position: position,
              ),

              // ── Info body (scrollable) ────────────────────────────────
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Player name ────────────────────────────────────
                      Text(
                        playerName,
                        style: const TextStyle(
                          color: HETheme.pfTextPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.1,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      if (club != null || nationality != null) ...[
                        const SizedBox(height: 14),
                        Container(height: 1, color: HETheme.pfBorder),
                        const SizedBox(height: 12),
                      ],

                      // ── Club row ───────────────────────────────────────
                      if (club != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              CardLogoWidget(
                                name: club!,
                                size: 30,
                                logoUrl: clubLogoUrl,
                                accentColor: tier.accentColor,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  club!,
                                  style: const TextStyle(
                                    color: HETheme.pfTextPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // ── Nationality row ────────────────────────────────
                      if (nationality != null)
                        Row(
                          children: [
                            FlagWidget(nationality: nationality!, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                nationality!,
                                style: const TextStyle(
                                  color: HETheme.pfTextPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),

                      // ── Alt positions ──────────────────────────────────
                      if (altPositions.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Container(height: 1, color: HETheme.pfBorder),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text(
                              'ALT',
                              style: TextStyle(
                                color: HETheme.pfTextSecondary,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: altPositions
                                  .map(
                                    (pos) =>
                                        _AltPositionChip(pos: pos, tier: tier),
                                  )
                                  .toList(),
                            ),
                          ],
                        ),
                      ],

                      // ── Stats block ────────────────────────────────────
                      if (_hasStats) ...[
                        const SizedBox(height: 14),
                        Container(height: 1, color: HETheme.pfBorder),
                        const SizedBox(height: 12),
                        _StatBlock(
                          pace: pace,
                          shooting: shooting,
                          passing: passing,
                          dribbling: dribbling,
                          defending: defending,
                          physical: physical,
                          tier: tier,
                        ),
                      ],

                      // ── Chemistry bonuses ──────────────────────────────
                      if (chemistryBonuses.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Container(height: 1, color: HETheme.pfBorder),
                        const SizedBox(height: 12),
                        _ChemistrySection(
                          ownerClub: club,
                          bonuses: chemistryBonuses,
                          lineup: lineup,
                          tier: tier,
                        ),
                      ],

                      // ── Pick button (selection cards only) ─────────────
                      if (onPick != null) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 46,
                          child: ElevatedButton(
                            onPressed: onPick,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: tier.accentColor,
                              foregroundColor: Colors.black.withValues(
                                alpha: 0.88,
                              ),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                              ),
                            ),
                            child: const Text('PICK'),
                          ),
                        ),
                      ],
                    ],
                  ), // Column
                ), // SingleChildScrollView
              ), // Flexible
            ],
          ), // Container
        ), // ConstrainedBox
      ),
    );
  }
}

// ── Hero image section ────────────────────────────────────────────────────────

class _HeroImage extends StatelessWidget {
  const _HeroImage({
    required this.playerName,
    required this.club,
    required this.primaryColorHex,
    required this.secondaryColorHex,
    required this.tertiaryColorHex,
    required this.numberSeed,
    required this.kitNumber,
    required this.kitPattern,
    required this.tier,
    required this.rating,
    required this.position,
  });

  final String playerName;
  final String? club;
  final String? primaryColorHex;
  final String? secondaryColorHex;
  final String? tertiaryColorHex;
  final String? numberSeed;
  final int? kitNumber;
  final KitPattern? kitPattern;
  final CardTier tier;
  final int rating;
  final String position;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: Stack(
        fit: StackFit.expand,
        children: [
          JerseyBack(
            playerName: playerName,
            club: club ?? '',
            primaryColorHex: primaryColorHex,
            secondaryColorHex: secondaryColorHex,
            tertiaryColorHex: tertiaryColorHex,
            numberSeed: numberSeed,
            kitNumber: kitNumber,
            kitPattern: kitPattern,
            fit: JerseyFit.contain,
          ),
          // Bottom vignette
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 72,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xF50F1520)],
                ),
              ),
            ),
          ),
          // Top fade for close button legibility
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 52,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xBB000000), Colors.transparent],
                ),
              ),
            ),
          ),
          // Combined rating + position badge — overlaid bottom-left
          Positioned(
            bottom: 10,
            left: 14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$rating',
                  style: TextStyle(
                    color: tier.accentColor,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                    shadows: const [
                      Shadow(color: Colors.black, blurRadius: 6),
                      Shadow(color: Colors.black, blurRadius: 12),
                    ],
                  ),
                ),
                Text(
                  position,
                  style: TextStyle(
                    color: tier.accentColor.withValues(alpha: 0.90),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
              ],
            ),
          ),
          // Close button
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 17,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Alt position chip ─────────────────────────────────────────────────────────

class _AltPositionChip extends StatelessWidget {
  const _AltPositionChip({required this.pos, required this.tier});

  final String pos;
  final CardTier tier;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tier.accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: tier.accentColor.withValues(alpha: 0.35)),
      ),
      child: Text(
        pos,
        style: TextStyle(
          color: tier.accentColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Stat block ────────────────────────────────────────────────────────────────

class _StatBlock extends StatelessWidget {
  const _StatBlock({
    required this.pace,
    required this.shooting,
    required this.passing,
    required this.dribbling,
    required this.defending,
    required this.physical,
    required this.tier,
  });

  final int pace;
  final int shooting;
  final int passing;
  final int dribbling;
  final int defending;
  final int physical;
  final CardTier tier;

  @override
  Widget build(BuildContext context) {
    final stats = [
      ('PAC', pace),
      ('SHO', shooting),
      ('PAS', passing),
      ('DRI', dribbling),
      ('DEF', defending),
      ('PHY', physical),
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.2,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: stats
          .map((s) => _StatCell(label: s.$1, value: s.$2, tier: tier))
          .toList(),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    required this.tier,
  });

  final String label;
  final int value;
  final CardTier tier;

  Color get _barColor {
    if (value >= 80) return HETheme.pfSuccess;
    if (value >= 65) return HETheme.pfWarning;
    return HETheme.pfDanger;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceRaised,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: HETheme.pfTextSecondary,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                '$value',
                style: TextStyle(
                  color: _barColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: value / 99.0,
              minHeight: 3,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(_barColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Chemistry bonus section ───────────────────────────────────────────────────

class _ChemistrySection extends StatelessWidget {
  const _ChemistrySection({
    required this.bonuses,
    required this.lineup,
    required this.tier,
    this.ownerClub,
  });

  final List<ChemistryBonus> bonuses;
  final List<LineupCard> lineup;
  final CardTier tier;
  final String? ownerClub;

  @override
  Widget build(BuildContext context) {
    final activeIndices = ChemistryEvaluator.activeSlotIndices(
      bonuses,
      lineup,
      ownerClub: ownerClub,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              'CHEMISTRY',
              style: TextStyle(
                color: HETheme.pfTextSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${activeIndices.length}/${bonuses.length}',
              style: TextStyle(
                color: activeIndices.isNotEmpty
                    ? HETheme.pfSuccess
                    : HETheme.pfTextSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Plain-language, ranked (strongest/closest-to-complete first) —
        // strictly more informative than the flat original-order list this
        // replaces, reading the exact same bonuses/lineup/ownerClub inputs.
        FitNoteCard(bonuses: bonuses, lineup: lineup, ownerClub: ownerClub),
        const SizedBox(height: 6),
        // Card chem reward summary — sum of satisfied tier rewards
        _CardChemRewardBadge(
          earnedReward: ChemistryEvaluator.earnedReward(
            bonuses,
            lineup,
            ownerClub: ownerClub,
          ),
        ),
      ],
    );
  }
}

class _CardChemRewardBadge extends StatelessWidget {
  const _CardChemRewardBadge({required this.earnedReward});

  /// Sum of satisfied tier rewards on this card (0..12).
  final int earnedReward;

  @override
  Widget build(BuildContext context) {
    final active = earnedReward > 0;
    final color = active ? HETheme.pfSuccess : HETheme.pfTextSecondary;
    final bg = active
        ? HETheme.pfSuccess.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.04);
    final border = active
        ? HETheme.pfSuccess.withValues(alpha: 0.40)
        : Colors.white.withValues(alpha: 0.07);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Card chemistry reward',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            '+$earnedReward pts',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
