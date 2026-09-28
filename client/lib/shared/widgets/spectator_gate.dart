import 'package:flutter/widgets.dart';

/// Wraps gameplay-action UI so a spectator's taps are structurally
/// non-interactive — not "sends an action the server then rejects", not
/// "silently no-ops deep inside some button's onPressed", but genuinely
/// removed from hit-testing at the UI layer, with no round-trip to the
/// server at all. This is the one, reusable mechanism every gameplay-action
/// surface (the draft/subs/ability side panel, the ability-draft screen)
/// wraps itself in — the specific taps a spectator must never be able to
/// trigger, not general in-game navigation (pitch tab switching, card
/// details, help dialogs), which stays fully usable for a spectator.
///
/// Deliberately a tiny, standalone, directly-testable widget rather than
/// inlining `IgnorePointer(ignoring: isSpectating, ...)` at each call site —
/// one thing to verify correct, reused everywhere it's needed.
class SpectatorGate extends StatelessWidget {
  const SpectatorGate({
    super.key,
    required this.isSpectating,
    required this.child,
  });

  final bool isSpectating;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(ignoring: isSpectating, child: child);
  }
}
