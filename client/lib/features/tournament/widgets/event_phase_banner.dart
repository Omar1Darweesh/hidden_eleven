import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';

/// The tournament's "live event status" surface — reusable shell for
/// whatever the current phase needs to say (draw, ready check, round live,
/// round complete, tournament complete). Generalizes what was previously a
/// screen-local `_buildPhaseBanner` method in `TournamentHubScreen` into a
/// standalone, presentation-only widget: the screen still computes
/// `accent`/`icon`/`title`/`subtitle`/deadline exactly as before and simply
/// hands them in, rather than building the `Container` inline.
///
/// Pure layout — no phase logic, no state, no animation.
class EventPhaseBanner extends StatelessWidget {
  const EventPhaseBanner({
    super.key,
    required this.accent,
    required this.icon,
    required this.title,
    this.subtitle,
    this.titleTrailing,
    this.trailing,
    this.body,
  });

  final Color accent;
  final IconData icon;
  final String title;
  final String? subtitle;

  /// Small inline element right after the title (e.g. the ready-check
  /// [InlineHelp] tooltip).
  final Widget? titleTrailing;

  /// Right-aligned element at the top of the banner (e.g. the countdown
  /// chip).
  final Widget? trailing;

  /// Phase-specific content below the header row (e.g. the ready-check
  /// progress ring + chips + button, or the "GO TO RESULT PAGE" CTA).
  final Widget? body;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      decoration: BoxDecoration(
        // Layered plum glass rather than a flat accent wash: the accent reads
        // along the leading edge and fades out across the surface, so the
        // banner announces its phase without becoming a coloured slab that
        // competes with the text on it.
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color.lerp(HETheme.pfSurfaceRaised, accent, 0.18)!,
            HETheme.pfSurfaceDeep,
          ],
          stops: const [0.0, 0.72],
        ),
        borderRadius: HEShape.lg,
        border: Border.all(color: accent.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.15),
            blurRadius: 24,
            spreadRadius: -6,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Angular accent edge — the lower-third signature. Purely
          // decorative and non-interactive; the phase is always also carried
          // by the icon and the title text.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: CustomPaint(
                size: const Size(26, double.infinity),
                painter: _PhaseAccentEdgePainter(color: accent),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    // Hex-motif icon chip.
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.16),
                        borderRadius: HEShape.md,
                        border: Border.all(
                          color: accent.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Icon(icon, color: accent, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  style: TextStyle(
                                    color: accent,
                                    fontSize: 17,
                                    height: 1.15,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (titleTrailing != null) ...[
                                const SizedBox(width: 6),
                                titleTrailing!,
                              ],
                            ],
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              subtitle!,
                              style: const TextStyle(
                                color: HETheme.pfTextSecondary,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    ?trailing,
                  ],
                ),
                if (body != null) ...[const SizedBox(height: 14), body!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The banner's leading angular edge — a tapered accent bar with a chamfered
/// corner, echoing the hex motif used on focus-level fixture capsules.
class _PhaseAccentEdgePainter extends CustomPainter {
  const _PhaseAccentEdgePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const barWidth = 4.0;
    final chamfer = size.width * 0.42;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(barWidth, 0)
      ..lineTo(barWidth, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color,
            color.withValues(alpha: 0.35),
          ],
        ).createShader(Offset.zero & size),
    );

    // A short diagonal tick off the bar, top and bottom — the "broadcast"
    // corner detail.
    final tick = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.5);

    canvas.drawLine(
      const Offset(barWidth + 2, 6),
      Offset(barWidth + 2 + chamfer, 6),
      tick,
    );
    canvas.drawLine(
      Offset(barWidth + 2, size.height - 6),
      Offset(barWidth + 2 + chamfer, size.height - 6),
      tick,
    );
  }

  @override
  bool shouldRepaint(_PhaseAccentEdgePainter old) => old.color != color;
}
