import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/models/ability.dart';

/// One player's card in the reveal sequence: face-down (a generic hidden
/// slot) until it's this player's turn to reveal, then flips to show their
/// ability's icon/colour/name with a short per-type flourish.
///
/// Uses a scale+fade cross-fade rather than a 3D `Transform(rotateY: …)`
/// flip — this app has a known Impeller/OpenGLES instability with 3D
/// perspective transforms on some Android emulator GPU configs (see
/// AndroidManifest's `EnableImpeller=false` fallback), so every other
/// reveal surface in the app already avoids true 3D card flips. A crisp
/// scale+fade reads just as "flip-like" without that risk.
class AbilityRevealCard extends StatelessWidget {
  const AbilityRevealCard({
    super.key,
    required this.playerName,
    required this.isYou,
    this.type,
    this.revealed = false,
    this.highlighted = false,
  });

  final String playerName;
  final bool isYou;

  /// Null = face-down (not revealed yet, or nothing to show — e.g. this
  /// player discarded, which is never shown even after reveal).
  final AbilityType? type;
  final bool revealed;

  /// The card currently being resolved in the sequence — gets a stronger
  /// glow/scale so attention is unambiguous even with several cards on
  /// screen at once.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final meta = type != null ? AbilityMeta.of(type!) : null;
    final showFace = revealed && meta != null;
    final accent = showFace ? meta.color : HETheme.pfTextMuted;

    return AnimatedScale(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      scale: highlighted ? 1.08 : 1.0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        width: 92,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: showFace
              ? accent.withValues(alpha: 0.14)
              : HETheme.pfSurfaceRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: highlighted
                ? accent
                : accent.withValues(alpha: showFace ? 0.5 : 0.3),
            width: highlighted ? 2 : 1,
          ),
          boxShadow: highlighted
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.45),
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: Tween(begin: 0.55, end: 1.0).animate(
                  CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
                ),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: showFace
                  ? Icon(
                      meta.icon,
                      key: ValueKey(type),
                      color: accent,
                      size: 26,
                    )
                  : Icon(
                      Icons.help_outline_rounded,
                      key: const ValueKey('facedown'),
                      color: HETheme.pfTextMuted,
                      size: 24,
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              isYou ? 'You' : playerName,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isYou ? HETheme.pfAccentViolet : HETheme.pfTextSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (showFace) ...[
              const SizedBox(height: 2),
              Text(
                meta.name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: accent,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
