import 'package:flutter/material.dart';
import 'package:hidden_eleven/features/game/models/ability.dart';

/// Shared ability-effect visuals for a player card — captain, red card, and
/// sub-swap — used identically wherever a card can appear: the pitch
/// (`pitch_view.dart`) and the bench (`subs_panel.dart`). Previously each
/// screen re-implemented its own version of these (subs_panel.dart had its
/// own duplicated sub-swap badge and no captain/red-card treatment at all),
/// which is exactly the kind of drift this file exists to prevent — the
/// server already tags a card's ability state the same way regardless of
/// where it currently sits (pitch or bench, see `_serializePitches`/
/// `_serializeSubSlot` in game.service.ts), so the client's presentation of
/// that state should be identical too.
///
/// Every widget here is purely visual and position-agnostic — callers wrap
/// it in their own `Positioned`/`Stack` to match their own card layout.

// Getters (not consts) — each reads through AbilityMeta.of(...), which
// prefers the admin-configured colour once AbilityMeta.ensureLoaded() has
// resolved (see game_screen.dart's bootstrap call), falling back to the
// same built-in hex values these used to hardcode directly. Safe to read
// on every build: AbilityMeta.of is a plain Map lookup, not a network call.
Color get kAbilityRedCard => AbilityMeta.of(AbilityType.red).color;
Color get kAbilityCaptainGold => AbilityMeta.of(AbilityType.captain).color;
Color get kAbilitySubSwapCyan => AbilityMeta.of(AbilityType.sub).color;
Color get kAbilityCoachPurple => AbilityMeta.of(AbilityType.coach).color;

/// Gently pulses its child (scale) to draw the eye to an ability badge
/// without being distracting.
class PulseBadge extends StatefulWidget {
  const PulseBadge({super.key, required this.child});
  final Widget child;

  @override
  State<PulseBadge> createState() => _PulseBadgeState();
}

class _PulseBadgeState extends State<PulseBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(
        begin: 1.0,
        end: 1.16,
      ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}

/// Gold "C" armband — this card is captained (its chemistry is doubled).
class CaptainArmbandBadge extends StatelessWidget {
  const CaptainArmbandBadge({super.key, this.size = 16});
  final double size;

  @override
  Widget build(BuildContext context) {
    return PulseBadge(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: kAbilityCaptainGold,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.5),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: kAbilityCaptainGold.withValues(alpha: 0.7),
              blurRadius: 5,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          'C',
          style: TextStyle(
            color: Colors.black,
            fontSize: size * 0.625,
            fontWeight: FontWeight.w900,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

/// Small red rectangular "card" icon badge — this card was red-carded (its
/// chemistry is nullified; its rating still counts).
class RedCardIconBadge extends StatelessWidget {
  const RedCardIconBadge({super.key, this.width = 13, this.height = 17});
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return PulseBadge(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: kAbilityRedCard,
          borderRadius: BorderRadius.circular(2.5),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.85),
            width: 1,
          ),
        ),
      ),
    );
  }
}

/// Full-card red wash + border — draws over the whole card body to make a
/// red-carded card unmistakable at a glance, not just via the small icon.
class RedCardWashOverlay extends StatelessWidget {
  const RedCardWashOverlay({super.key, this.borderRadius = 8});
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          color: kAbilityRedCard.withValues(alpha: 0.22),
          border: Border.all(
            color: kAbilityRedCard.withValues(alpha: 0.85),
            width: 2,
          ),
        ),
      ),
    );
  }
}

/// Cyan swap-arrows badge — this card was swapped between squads by a Sub
/// ability card.
class SubSwapBadge extends StatelessWidget {
  const SubSwapBadge({super.key, this.size = 16});
  final double size;

  @override
  Widget build(BuildContext context) {
    return PulseBadge(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: kAbilitySubSwapCyan,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.5),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: kAbilitySubSwapCyan.withValues(alpha: 0.7),
              blurRadius: 5,
            ),
          ],
        ),
        child: Icon(
          Icons.swap_horiz_rounded,
          size: size * 0.7,
          color: Colors.black,
        ),
      ),
    );
  }
}

/// Card-level highlight — this card was given an extra playable position by a
/// Coach ability card (it can now also play its coached position for the rest
/// of the match). Purely additive: it grants no protection from other effects.
///
/// Deliberately NOT another small badge icon: the top-right corner (where a
/// badge would go) already hosts the chemistry-reward badge, and top-left/
/// bottom-left/bottom-right are already claimed by the sub-state, red-card,
/// and captain badges respectively — a 5th small icon there just adds visual
/// noise. Instead this draws a purple outer ring + soft glow around the
/// WHOLE card, which reads clearly at a glance without competing for space
/// in that already-crowded badge cluster.
///
/// Meant to be the LAST child of the Stack that composes a player card (pitch
/// tile or bench card), sized via `Positioned.fill` so it traces the card's
/// own bounds exactly. `IgnorePointer` keeps it purely decorative — it never
/// intercepts taps meant for the card underneath.
class CoachedCardHighlight extends StatelessWidget {
  const CoachedCardHighlight({super.key, this.borderRadius = 8});
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: kAbilityCoachPurple, width: 2),
          boxShadow: [
            BoxShadow(
              color: kAbilityCoachPurple.withValues(alpha: 0.55),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}
