import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/models/ability.dart';

/// The two-line reveal copy for whichever ability is currently resolving:
/// a headline ("Omar reveals: Captain") and a plain-language resolution
/// sentence built server-side (`activation.summary`, e.g. "Captain on Van
/// de Ven" or "Red Card on Bastoni (Omar)"). Swaps content with a fade+slide
/// whenever the underlying activation changes, keyed by player id so two
/// same-type reveals in a row still visibly transition.
class AbilityResolutionBanner extends StatelessWidget {
  const AbilityResolutionBanner({
    super.key,
    required this.activation,
    required this.isYou,
  });

  final AbilityActivation activation;
  final bool isYou;

  @override
  Widget build(BuildContext context) {
    final meta = AbilityMeta.of(activation.type);
    final who = isYou ? 'You' : activation.byName;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.15),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
      child: Column(
        key: ValueKey(
          '${activation.byPlayerId}-${activation.type}-${activation.summary}',
        ),
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(meta.icon, color: meta.color, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '$who reveals: ${meta.name}',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: meta.color,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            activation.summary,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: HETheme.pfTextPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
