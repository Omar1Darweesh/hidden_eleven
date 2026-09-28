import 'package:hidden_eleven/features/game/models/game_state.dart';

/// The local player's own step through the `ability_activation` game phase.
/// Purely a view over [GameState] — no state of its own, so it's always
/// correct on a fresh reconnect without needing any animation history.
///
/// Note this does NOT cover the reveal/resolved presentation — that's owned
/// by `AbilityRevealPlaybackController` (see ability_reveal_provider.dart),
/// which paces the already-authoritative `abilityActivations` list locally.
/// This enum only decides what `AbilityActivationPanel` itself should show
/// while the room is still mid-phase and not yet revealed.
enum AbilitySelectPhase {
  /// Not in the ability-activation phase at all (before it, after it, or
  /// abilities are disabled for this room).
  none,

  /// The local player hasn't committed yet — show the picker + confirm UI.
  select,

  /// The local player has committed (used or discarded) but the server
  /// hasn't revealed yet (not everyone has locked in). Read-only, hidden.
  lockedWait,

  /// The server has run its reveal pass. The picker/lock UI has nothing
  /// left to show — the reveal overlay (driven separately) takes over.
  revealed,
}

AbilitySelectPhase computeAbilitySelectPhase(GameState game) {
  if (game.status != 'ability_activation') return AbilitySelectPhase.none;
  if (game.abilityActivationRevealed) return AbilitySelectPhase.revealed;
  final mine = game.myAbility;
  if (mine == null || mine.isPending) return AbilitySelectPhase.select;
  return AbilitySelectPhase.lockedWait;
}

/// Per-player lock status for the room-progress row shown to everyone during
/// `ability_select`/`ability_locked_wait`. Never reveals ability TYPE.
enum AbilityLockStatus { choosing, locked, disconnected }

AbilityLockStatus computeAbilityLockStatus({
  required bool isConnected,
  required bool hasResolved,
}) {
  if (!isConnected) return AbilityLockStatus.disconnected;
  return hasResolved ? AbilityLockStatus.locked : AbilityLockStatus.choosing;
}
