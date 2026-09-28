import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/widgets/card_details_modal.dart';
import 'package:hidden_eleven/shared/widgets/jersey_back.dart';

/// Unified FIFA-style player card used everywhere in the game UI.
///
/// Aspect ratio is always 3 : 4.2 (w : h) — never overflows regardless
/// of the parent's dimensions.
///
/// Parameters:
///   [card]     — the player data; required when [faceDown] is false.
///   [faceDown] — shows the card back only; no player data is revealed.
///   [onPick]   — if set, a PICK button appears at the bottom of the front face.
///   [onTap]    — tap handler for the whole card (typically opens details sheet).
class PlayerCard extends StatelessWidget {
  const PlayerCard({
    super.key,
    this.card,
    this.faceDown = false,
    this.onPick,
    this.onTap,
  });

  final CandidateCard? card;
  final bool faceDown;
  final VoidCallback? onPick;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = faceDown
        ? const _CardBack()
        : _CardFront(card: card!, onPick: onPick, onTap: onTap);

    // Normally this card derives its height from its width via AspectRatio
    // (3 : 4.2), which is correct when the parent constrains only one axis
    // (the common case: a width-bounded slot in a Wrap/grid).
    //
    // But when the parent already dictates a DEFINITE box (both axes bounded)
    // AspectRatio is at best redundant and at worst dangerous: under an
    // IntrinsicHeight ancestor it triggered a main-thread hang (ANR) on
    // Android's Impeller/OpenGLES backend at the subs picked-bench site (see
    // subs_panel.dart's _PickedSlot). When the box is already fully
    // constrained, fill it directly and skip the aspect-ratio pass — every
    // existing fully-constrained caller (Positioned.fill / AnimatedPositioned
    // with width+height) was already forcing a tight box, so AspectRatio was a
    // no-op there and this is behaviourally identical for them.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.hasBoundedWidth && constraints.hasBoundedHeight) {
          return SizedBox.expand(child: content);
        }
        return AspectRatio(aspectRatio: 3 / 4.2, child: content);
      },
    );
  }
}

// ── Card back ─────────────────────────────────────────────────────────────────

class _CardBack extends StatelessWidget {
  const _CardBack();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, box) {
        final w = box.maxWidth;
        return Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [HETheme.pfSurfaceDeep, HETheme.pfBgVoid],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: HETheme.pfAccentViolet.withValues(alpha: 0.40),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: HETheme.pfAccentViolet.withValues(alpha: 0.18),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _BackPatternPainter()),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.shield_rounded,
                      color: HETheme.pfAccentViolet.withValues(alpha: 0.28),
                      size: w * 0.38,
                    ),
                    SizedBox(height: w * 0.055),
                    Text(
                      'HIDDEN ELEVEN',
                      style: TextStyle(
                        color: HETheme.pfAccentViolet.withValues(alpha: 0.38),
                        fontSize: (w * 0.065).clamp(7.0, 12.0),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BackPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = HETheme.pfAccentViolet.withValues(alpha: 0.030)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    const spacing = 14.0;
    for (double d = -size.height; d < size.width + size.height; d += spacing) {
      canvas.drawLine(
        Offset(d, 0),
        Offset(d + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BackPatternPainter old) => false;
}

// ── Card front ────────────────────────────────────────────────────────────────

class _CardFront extends StatelessWidget {
  const _CardFront({required this.card, this.onPick, this.onTap});

  final CandidateCard card;
  final VoidCallback? onPick;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tier = CardTier.forCard(card.rating, card.cardStyle);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [tier.gradientTop, tier.gradientBottom],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(12),
          // Double stroke reads as a bevelled metal edge rather than a flat
          // tinted outline — a thin bright inner line catching the light,
          // with the tier colour doing the actual work just inside it.
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.20),
            width: 2.2,
          ),
          boxShadow: [
            BoxShadow(
              color: tier.accentColor.withValues(alpha: 0.22),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Inner tier-coloured edge, drawn just inside the bright bevel.
            Positioned.fill(
              child: Container(
                margin: const EdgeInsets.all(0.8),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: tier.borderColor.withValues(alpha: 0.65),
                    width: 1,
                  ),
                ),
              ),
            ),
            // Brushed-metal texture — the actual "surface" every tier is
            // missing without it: a flat gradient reads as a colour swatch,
            // this reads as a manufactured card stock.
            Positioned.fill(child: CustomPaint(painter: _CardTexturePainter())),
            LayoutBuilder(
              builder: (ctx, box) {
                final w = box.maxWidth;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Image zone — takes all height above the info strip
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _CardImage(card: card, tier: tier, width: w),
                          const Positioned.fill(child: _TopFade()),
                          const Positioned.fill(child: _Vignette()),
                          const Positioned.fill(child: _TopSheen()),
                          Positioned(
                            top: 5,
                            left: 5,
                            child: _RatingBadge(
                              rating: card.rating,
                              tier: tier,
                              w: w,
                            ),
                          ),
                          Positioned(
                            top: 5,
                            right: 5,
                            child: _PositionBadge(
                              position: card.primaryPosition,
                              tier: tier,
                              w: w,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Info strip
                    _InfoStrip(card: card, tier: tier, onPick: onPick, w: w),
                  ],
                );
              },
            ),
            // Foil sweep — gold/Icon/Hero cards only, see CardTier.isPremium.
            // Drawn last so it glints over the badges and info strip too,
            // the way a real foil card's finish covers the whole face.
            if (tier.isPremium)
              const Positioned.fill(child: IgnorePointer(child: _FoilSweep())),
          ],
        ),
      ),
    );
  }
}

// ── Rating badge ──────────────────────────────────────────────────────────────

class _RatingBadge extends StatelessWidget {
  const _RatingBadge({
    required this.rating,
    required this.tier,
    required this.w,
  });
  final int rating;
  final CardTier tier;
  final double w;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        '$rating',
        style: TextStyle(
          color: tier.accentColor,
          fontSize: (w * 0.22).clamp(13.0, 24.0),
          fontWeight: FontWeight.w900,
          height: 1.05,
        ),
      ),
    );
  }
}

// ── Position badge ────────────────────────────────────────────────────────────

class _PositionBadge extends StatelessWidget {
  const _PositionBadge({
    required this.position,
    required this.tier,
    required this.w,
  });
  final String position;
  final CardTier tier;
  final double w;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: tier.accentColor.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: tier.accentColor.withValues(alpha: 0.50)),
      ),
      child: Text(
        position,
        style: TextStyle(
          color: tier.accentColor,
          fontSize: (w * 0.09).clamp(8.0, 11.0),
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ── Info strip ────────────────────────────────────────────────────────────────

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({
    required this.card,
    required this.tier,
    required this.onPick,
    required this.w,
  });
  final CandidateCard card;
  final CardTier tier;
  final VoidCallback? onPick;
  final double w;

  @override
  Widget build(BuildContext context) {
    final ph = (w * 0.07).clamp(4.0, 10.0);
    final vg = (w * 0.025).clamp(1.5, 4.0);

    return Container(
      color: tier.gradientBottom,
      padding: EdgeInsets.fromLTRB(ph, w * 0.045, ph, w * 0.055),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Player name
          Text(
            card.playerName,
            style: TextStyle(
              color: Colors.white,
              fontSize: (w * 0.115).clamp(8.5, 14.0),
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          // Club logo + country flag — omit on very small cards
          if ((card.club != null || card.nationality != null) && w >= 80) ...[
            SizedBox(height: vg),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (card.club != null)
                  CardLogoWidget(
                    name: card.club!,
                    size: (w * 0.20).clamp(12.0, 22.0),
                    logoUrl: card.clubLogoUrl,
                    accentColor: tier.accentColor,
                  ),
                if (card.club != null && card.nationality != null)
                  SizedBox(width: (w * 0.05).clamp(3.0, 7.0)),
                if (card.nationality != null)
                  FlagWidget(
                    nationality: card.nationality!,
                    size: (w * 0.16).clamp(10.0, 18.0),
                  ),
              ],
            ),
          ],

          // Alt positions — only when wide enough
          if (card.naturalAltPositions.isNotEmpty && w >= 100) ...[
            SizedBox(height: vg),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: card.naturalAltPositions
                  .take(2)
                  .map(
                    (pos) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: tier.accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: tier.accentColor.withValues(alpha: 0.40),
                          ),
                        ),
                        child: Text(
                          pos,
                          style: TextStyle(
                            color: tier.accentColor,
                            fontSize: (w * 0.078).clamp(6.0, 9.5),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],

          // PICK button
          if (onPick != null) ...[
            SizedBox(height: w * 0.04),
            SizedBox(
              height: (w * 0.22).clamp(22.0, 32.0),
              child: ElevatedButton(
                onPressed: onPick,
                style: ElevatedButton.styleFrom(
                  backgroundColor: tier.accentColor,
                  foregroundColor: Colors.black.withValues(alpha: 0.88),
                  padding: EdgeInsets.zero,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  textStyle: TextStyle(
                    fontSize: (w * 0.1).clamp(7.5, 12.0),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
                child: const Text('PICK'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Card surface texture ─────────────────────────────────────────────────────

/// Diagonal brushed-metal hairlines + a soft off-centre highlight, painted
/// over every card's gradient. Kept low-alpha throughout: this must read as
/// "card stock has a surface" at a glance, not as visible stripes competing
/// with the jersey/name/badges on top of it.
class _CardTexturePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Soft highlight, as if a light is grazing the card from the upper-left —
    // this is what makes the surface read as embossed/manufactured rather
    // than a printed flat colour.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.6, -0.9),
          radius: 1.1,
          colors: [
            Colors.white.withValues(alpha: 0.07),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(Offset.zero & size),
    );

    // Brushed hairlines, angled 35° — fine enough to read as a texture, not
    // as a repeating pattern.
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.025)
      ..strokeWidth = 1.0;
    const spacing = 6.0;
    final span = size.width + size.height;
    for (double d = -span; d < span; d += spacing) {
      canvas.drawLine(
        Offset(d, 0),
        Offset(d - size.height * 0.7, size.height),
        line,
      );
    }
  }

  @override
  bool shouldRepaint(_CardTexturePainter old) => false;
}

// ── Foil sweep (premium tiers only) ──────────────────────────────────────────

/// A soft diagonal band of light that drifts across the card on a slow loop —
/// the "foil" finish that marks a gold/Icon/Hero card as physically special,
/// the same cue FIFA/FUT cards use. Gated to [CardTier.isPremium] in
/// [_CardFront] so it stays a signal, not decoration on every card.
class _FoilSweep extends StatefulWidget {
  const _FoilSweep();

  @override
  State<_FoilSweep> createState() => _FoilSweepState();
}

class _FoilSweepState extends State<_FoilSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      // Slow and slightly irregular-feeling via the curve below — a fast or
      // perfectly linear sweep reads as a loading spinner, not a material
      // finish.
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Sweeps from off the top-left to off the bottom-right and holds
        // briefly off-screen before looping, via the eased position below —
        // a foil catches the light occasionally, not on a constant metronome.
        final t = Curves.easeInOutCubic.transform(
          (_controller.value * 1.4).clamp(0.0, 1.0),
        );
        final pos = -0.6 + t * 2.2;
        // A plain gradient container, not a ShaderMask: the gradient's own
        // transparent stops do normal alpha compositing over whatever's
        // underneath, so this only ever ADDS a highlight — nothing here can
        // paint an opaque layer over the card.
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(pos - 0.35, -1),
              end: Alignment(pos + 0.35, 1),
              colors: const [
                Colors.transparent,
                Color(0x40FFFFFF),
                Colors.transparent,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

// ── Player image (generated jersey — no third-party photography) ────────────

class _CardImage extends StatelessWidget {
  const _CardImage({
    required this.card,
    required this.tier,
    required this.width,
  });
  final CandidateCard card;
  final CardTier tier;

  /// Kept for API parity with call sites that still pass it; no longer used
  /// for decode-size capping now that this renders a generated jersey rather
  /// than a network image.
  final double width;

  @override
  Widget build(BuildContext context) {
    return JerseyBack(
      playerName: card.playerName,
      club: card.club ?? '',
      primaryColorHex: card.primaryColor,
      secondaryColorHex: card.secondaryColor,
      tertiaryColorHex: card.tertiaryColor,
      kitPattern: kitPatternFromName(card.kitPattern),
      numberSeed: card.cardId,
      kitNumber: card.kitNumber,
    );
  }
}

// ── Image overlays ────────────────────────────────────────────────────────────

// Both scrims are sized as a FRACTION of the image zone, not in fixed px.
// They were 48px and 52px, which on a compact card's ~85px-tall image zone
// overlapped into a near-opaque black blanket over the whole thing — the
// reason the artwork underneath looked muddy. They're also lighter now: they
// exist to keep the corner badges legible, and the jersey already carries its
// own outlined lettering, so it doesn't need a heavy scrim to sit on.
class _TopFade extends StatelessWidget {
  const _TopFade();
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: FractionallySizedBox(
        heightFactor: 0.34,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x73000000), Colors.transparent],
            ),
          ),
        ),
      ),
    );
  }
}

class _Vignette extends StatelessWidget {
  const _Vignette();
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        heightFactor: 0.30,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0xA6000000)],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopSheen extends StatelessWidget {
  const _TopSheen();
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: FractionallySizedBox(
        widthFactor: 0.55,
        heightFactor: 0.45,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.10),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
