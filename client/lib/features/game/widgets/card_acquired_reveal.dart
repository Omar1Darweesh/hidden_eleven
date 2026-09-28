import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_motion.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';

/// How long the reveal stays up before dismissing itself.
const Duration kCardAcquiredRevealDuration = Duration(milliseconds: 1800);

/// A short, non-blocking confirmation that a drafted player has been acquired
/// and which slot they filled.
///
/// **Purely presentational.** It is shown *after* the pick has already been
/// sent to the server — it never gates, delays or re-sends `pick_card`, and
/// the pitch continues to be filled from authoritative `game_state`. If the
/// server's next state arrives first, this simply confirms what is already on
/// the pitch; if the next turn begins while it is still visible, the host
/// force-dismisses it (see `onDismiss`).
///
/// Reduced motion renders the final composition immediately — same content,
/// same dismiss timing, no entrance animation.
class CardAcquiredReveal extends StatefulWidget {
  const CardAcquiredReveal({
    super.key,
    required this.card,
    required this.slotLabel,
    required this.onDismiss,
  });

  final CandidateCard card;

  /// The formation slot the card was drafted into, e.g. "LB" or "ST".
  final String slotLabel;

  final VoidCallback onDismiss;

  @override
  State<CardAcquiredReveal> createState() => _CardAcquiredRevealState();
}

class _CardAcquiredRevealState extends State<CardAcquiredReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: HEMotion.land,
  );

  bool _dismissed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.status == AnimationStatus.dismissed) {
      if (HEMotion.reduced(context)) {
        _controller.value = 1.0;
      } else {
        _controller.forward();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    // Self-dismiss. Deliberately a plain delayed callback rather than an
    // animation status listener, so the reveal's lifetime is identical with
    // and without motion.
    Future.delayed(kCardAcquiredRevealDuration, () {
      if (mounted) _dismiss();
    });
  }

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;

    return Semantics(
      label:
          'Acquired ${card.playerName}, rated ${card.rating}, '
          '${card.basePositionType}'
          '${card.club != null ? ', ${card.club}' : ''}, '
          'into ${widget.slotLabel}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: _dismiss,
        behavior: HitTestBehavior.opaque,
        child: FadeTransition(
          opacity: _controller,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(
              CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: HETheme.pfSurfaceDeep,
                borderRadius: HEShape.lg,
                border: Border.all(
                  color: HETheme.pfAccentViolet.withValues(alpha: 0.55),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: HETheme.pfAccentViolet.withValues(alpha: 0.22),
                    blurRadius: 28,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        color: HETheme.pfSuccess,
                        size: 15,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'SIGNED',
                        style: TextStyle(
                          color: HETheme.pfSuccess,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _PlayerPortrait(card: card),
                  const SizedBox(height: 12),
                  Text(
                    card.playerName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: HETheme.pfTextPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: [
                      _MetaChip(
                        text: '${card.rating}',
                        color: HETheme.pfGold,
                        icon: Icons.star_rounded,
                      ),
                      _MetaChip(
                        text: card.basePositionType,
                        color: HETheme.pfAccentViolet,
                      ),
                      if (card.club != null && card.club!.isNotEmpty)
                        _MetaChip(
                          text: card.club!,
                          color: HETheme.pfTextSecondary,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Destination slot — the "where did they go" answer.
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: HETheme.pfAccentViolet.withValues(alpha: 0.10),
                      borderRadius: HEShape.pill,
                      border: Border.all(
                        color: HETheme.pfAccentViolet.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.arrow_downward_rounded,
                          size: 14,
                          color: HETheme.pfAccentViolet,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Into ${widget.slotLabel}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: HETheme.pfAccentViolet,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerPortrait extends StatelessWidget {
  const _PlayerPortrait({required this.card});

  final CandidateCard card;

  @override
  Widget build(BuildContext context) {
    const size = 84.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceRaised,
        shape: BoxShape.circle,
        border: Border.all(
          color: HETheme.pfAccentViolet.withValues(alpha: 0.40),
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: (card.imageUrl != null && card.imageUrl!.isNotEmpty)
          ? Image.network(
              card.imageUrl!,
              fit: BoxFit.cover,
              // A missing portrait must never break the confirmation — the
              // name/rating/position below still answer "who did I get".
              errorBuilder: (_, _, _) => const _PortraitFallback(),
            )
          : const _PortraitFallback(),
    );
  }
}

class _PortraitFallback extends StatelessWidget {
  const _PortraitFallback();

  @override
  Widget build(BuildContext context) => const Center(
    child: Icon(
      Icons.person_rounded,
      color: HETheme.pfTextMuted,
      size: 36,
    ),
  );
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.text, required this.color, this.icon});

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: HEShape.pill,
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
