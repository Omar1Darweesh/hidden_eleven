import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hidden_eleven/app/routes.dart';
import 'package:hidden_eleven/app/theme.dart';
import 'package:hidden_eleven/features/subs/subs_panel.dart';
import 'package:hidden_eleven/features/subs/sub_swap_selection.dart';
import 'package:hidden_eleven/features/game/game_provider.dart';
import 'package:hidden_eleven/features/game/models/ability.dart';
import 'package:hidden_eleven/features/game/models/chemistry_vars.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/services/chemistry_evaluator.dart';
import 'package:hidden_eleven/features/game/widgets/abilities_help.dart';
import 'package:hidden_eleven/features/game/widgets/ability_activation_screen.dart';
import 'package:hidden_eleven/features/game/widgets/ability_draft_screen.dart';
import 'package:hidden_eleven/features/game/widgets/ability_log.dart';
import 'package:hidden_eleven/features/game/widgets/ability_reveal_overlay.dart';
import 'package:hidden_eleven/features/game/widgets/candidate_panel.dart';
import 'package:hidden_eleven/features/game/widgets/game_action_sheet.dart';
import 'package:hidden_eleven/features/game/widgets/hidden_pick_panel.dart';
import 'package:hidden_eleven/features/game/widgets/card_details_modal.dart';
import 'package:hidden_eleven/features/game/widgets/panel_header.dart';
import 'package:hidden_eleven/features/game/widgets/arena_background.dart';
import 'package:hidden_eleven/features/game/widgets/arena_frame.dart';
import 'package:hidden_eleven/features/game/widgets/arena_metrics.dart';
import 'package:hidden_eleven/features/game/widgets/match_bar.dart';
import 'package:hidden_eleven/features/game/widgets/mission_card.dart';
import 'package:hidden_eleven/features/game/widgets/squad_switcher.dart';
import 'package:hidden_eleven/features/game/widgets/tactical_order_sheet.dart';
import 'package:hidden_eleven/shared/widgets/settings_sheet.dart';
import 'package:hidden_eleven/features/game/widgets/pitch_view.dart';
import 'package:hidden_eleven/features/game/widgets/player_card.dart';
import 'package:hidden_eleven/features/game/widgets/scoring_panel.dart';
import 'package:hidden_eleven/features/game/widgets/card_acquired_reveal.dart';
import 'package:hidden_eleven/features/game/widgets/team_chemistry_summary.dart';
import 'package:hidden_eleven/features/game/widgets/waiting_banner.dart';
import 'package:hidden_eleven/features/lobby/models/server_event.dart';
import 'package:hidden_eleven/features/lobby/room_provider.dart';
import 'package:hidden_eleven/features/tournament/models/tournament_models.dart';
import 'package:hidden_eleven/features/tournament/providers/tournament_provider.dart';
import 'package:hidden_eleven/shared/ads/ad_config.dart';
import 'package:hidden_eleven/shared/ads/side_ad_rail.dart';
import 'package:hidden_eleven/shared/audio/audio_service.dart';
import 'package:hidden_eleven/shared/providers/local_presence_provider.dart';
import 'package:hidden_eleven/shared/providers/local_spectator_presence_provider.dart';
import 'package:hidden_eleven/shared/widgets/context_help_button.dart';
import 'package:hidden_eleven/shared/widgets/detail_bottom_sheet.dart';
import 'package:hidden_eleven/shared/widgets/he_button.dart';
import 'package:hidden_eleven/shared/widgets/help_dialog.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/shared/widgets/spectator_gate.dart';

/// Which top-level panel `_ActionPanel._buildContent` renders for a given
/// [GameState.status]. Extracted as a pure, public function (rather than
/// inlined `if (game.status == ...)` checks) so the routing decision itself
/// is directly unit-testable without pumping the full GameScreen widget tree
/// — which needs a fully wired ProviderScope/socket service to construct at
/// all. Same rationale as subs_panel.dart's `opponentStatusLabel` extraction.
enum GamePanelKind { abilityActivation, benchSelection, lineupEdit, turnBased }

GamePanelKind gamePanelKindFor(String status) => switch (status) {
  'ability_activation' => GamePanelKind.abilityActivation,
  'bench_selection' => GamePanelKind.benchSelection,
  'lineup_edit' => GamePanelKind.lineupEdit,
  _ => GamePanelKind.turnBased,
};

/// The chemistry total already delivered in the scoring preview — the exact
/// same sum `ScoringSummaryBar` prints as "+N chem". Read-only: it reuses
/// server-computed values and never evaluates chemistry itself.
int _chemistryTotal(ScoringPreview p) =>
    p.userChemTotal + p.cardChemTotal + p.lineLeaderBonus;

/// Draft & scoring help — explains the terms shown on the result page's
/// score breakdown (Raw Sum, Avg, DEF/MID/ATK, Final Score, chemistry) and
/// the chemistry-only-ability clarification, kept next to the screen it
/// describes rather than in one shared content file.
const _draftHelpSections = <HelpSection>[
  HelpSection('SQUAD RATING NUMBERS', [
    HelpEntry(
      'Raw Sum',
      'The plain total of all 11 pitch cards\' ratings, added up with no '
          'averaging or chemistry. A squad-power stat only — it is NOT your '
          'final score.',
    ),
    HelpEntry(
      'Avg',
      'The average rating across your 11 starters (Raw Sum ÷ 11).',
    ),
    HelpEntry(
      'DEF / MID / ATK',
      'The average rating within each line (defence / midfield / attack). '
          'An out-of-position card scores 0 for its line.',
    ),
  ]),
  HelpSection('FINAL SCORE', [
    HelpEntry(
      'How it\'s calculated',
      'Final Score = (DEF avg + MID avg + ATK avg) + chemistry bonuses '
          '(user challenges, card chemistry, line leaders) ± ability effects '
          '(Captain bonus, Yellow-card penalty, Red-card nullification).',
    ),
    HelpEntry(
      'What chemistry affects',
      'Chemistry bonuses only count for in-position, non-red-carded cards. '
          'Out-of-position cards contribute 0 to both their line average and '
          'their own chemistry.',
    ),
  ]),
  HelpSection('ABILITY CARDS', [
    HelpEntry(
      'Chemistry-only, not a match event',
      'The Red Card ability disables a targeted card\'s chemistry for '
          'scoring — it is pre-match/draft-phase logic only. It is NOT the '
          'same as a real red card shown in tournament match events.',
    ),
  ]),
];

/// Copy for the turn_auto_picked snackbar. Uses the timed-out player's
/// actual display name when it could be resolved from game.players, falling
/// back to the generic "Opponent" phrasing otherwise (unresolved id, empty
/// name, or a stale roster) — this is what makes an N>2 timeout say who
/// actually timed out instead of a generic, ambiguous "Opponent". Extracted
/// as a standalone function for the same testability reason as
/// subs_panel.dart's `opponentStatusLabel`.
String turnAutoPickedMessage({
  required bool isLocal,
  String? timedOutPlayerName,
}) {
  if (isLocal) return "Time's up! A card was picked for you.";
  if (timedOutPlayerName != null && timedOutPlayerName.isNotEmpty) {
    return '$timedOutPlayerName timed out.';
  }
  return 'Opponent timed out.';
}

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, required this.roomCode});
  final String roomCode;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  // 0 = local player; 1..n = other players in game.players order
  int _tabIndex = 0;

  /// Whether the start-of-game formation reveal animation has already played
  /// on this client (so it shows once, not on every rebuild or reconnect).
  bool _formationRevealPlayed = false;

  /// The just-drafted card being confirmed by [CardAcquiredReveal], plus the
  /// slot it went into, or null when no confirmation is showing.
  ///
  /// Captured at the moment the pick is sent — the send itself is never
  /// delayed by this (see `onCardPick`). Cleared when the reveal times out,
  /// is tapped, or the turn moves on, whichever happens first.
  CandidateCard? _acquiredCard;
  String? _acquiredSlotLabel;
  String? _acquiredTurnId;

  void _showCardAcquired(CandidateCard card, String slotLabel, String turnId) {
    setState(() {
      _acquiredCard = card;
      _acquiredSlotLabel = slotLabel;
      _acquiredTurnId = turnId;
    });
  }

  void _clearCardAcquired() {
    if (_acquiredCard == null) return;
    setState(() {
      _acquiredCard = null;
      _acquiredSlotLabel = null;
      _acquiredTurnId = null;
    });
  }

  /// The frozen ability-activation reveal batch currently animating, or null
  /// when no reveal is in progress. Captured once (see the ref.listen below)
  /// at the moment `abilityActivationRevealed` flips false→true WHILE this
  /// screen is already live — deliberately NOT re-derived from `game` on
  /// every rebuild, so the overlay keeps playing through the server's brief
  /// `ability_activation` → `lineup_edit` transition a few seconds later instead of
  /// being yanked away mid-animation. A reconnect (or a fresh mount that
  /// only ever observes `prev == null`) never captures this, so a client
  /// that missed the live moment lands straight on the final resolved board
  /// — exactly what "the server remains authoritative, no guessed replay"
  /// requires.
  List<AbilityActivation>? _abilityRevealBatch;
  List<GamePlayer> _abilityRevealPlayers = const [];

  /// Guards against navigating to the Result screen more than once — shared
  /// between the live isFinished-transition listener and the reconnect-time
  /// build check below, so a match that finishes while this screen is
  /// already mounted never fires both paths.
  bool _navigatedToResult = false;

  /// True once this widget has observed at least one non-null [GameState] —
  /// distinguishes "reconnecting straight into an already-finished match"
  /// (checked once, right here, on that very first observation) from "the
  /// match finished later while this screen was already live" (handled
  /// separately by the ref.listen transition below, which must keep
  /// respecting the tournament-hub-stay exception — see its own comment).
  bool _sawFirstGameState = false;

  /// Safety net for a stuck "waiting for game_state" state: a successful
  /// check_presence/room reconnect only proves the ROOM was restored — the
  /// separate game_state message can, for any number of reasons (a dropped
  /// packet mid-transit, a socket that silently died without either side
  /// noticing — see room_socket_service.dart's `.ready` fix — a server-side
  /// hiccup), simply never arrive. Without this, `game == null` renders a
  /// bare CircularProgressIndicator forever with no way out except force-
  /// closing the app — exactly the "black screen stuck on loading after
  /// rejoin" symptom. Started/cancelled in _watchForStuckLoad below.
  Timer? _gameLoadTimer;
  bool _gameLoadTimedOut = false;

  /// (Re)arms the stuck-load timer if there is currently no game to show.
  /// Idempotent — safe to call on every build.
  void _watchForStuckLoad() {
    if (ref.read(gameProvider) != null) {
      _gameLoadTimer?.cancel();
      _gameLoadTimer = null;
      return;
    }
    if (_gameLoadTimer != null) return;
    _gameLoadTimedOut = false;
    _gameLoadTimer = Timer(const Duration(seconds: 12), () {
      if (!mounted) return;
      if (ref.read(gameProvider) != null) return;
      setState(() => _gameLoadTimedOut = true);
    });
  }

  /// Retry action for the stuck-load screen: forces a fresh reconnect
  /// attempt (bypassing _maybeBootstrap's "already have a matching room"
  /// early-return, since that guard is exactly what's currently stuck) and
  /// re-arms the timeout.
  void _retryGameLoad() {
    setState(() => _gameLoadTimedOut = false);
    _gameLoadTimer?.cancel();
    _gameLoadTimer = null;
    final presence = ref.read(localPresenceProvider);
    final spectatorPresence = ref.read(localSpectatorPresenceProvider);
    if (presence != null && presence.roomCode == widget.roomCode) {
      ref.read(roomProvider.notifier).jumpIn();
    } else if (spectatorPresence != null &&
        spectatorPresence.roomCode == widget.roomCode) {
      ref.read(roomProvider.notifier).jumpInAsSpectator();
    }
    _watchForStuckLoad();
  }

  /// Navigates to the Result screen for a finished match, unless the
  /// tournament-hub exception applies (see call site comments) or this
  /// screen has already navigated once this session.
  void _goToResult(GameState game, {required bool respectTournamentHubStay}) {
    if (_navigatedToResult || !mounted) return;
    if (respectTournamentHubStay &&
        ref.read(tournamentCompleteProvider) != null) {
      return;
    }
    _navigatedToResult = true;
    context.goNamed(Routes.result, pathParameters: {'roomCode': game.roomCode});
  }

  // ── Substitution swap selection (ephemeral, local-only) ──────────────────
  // Source side: exactly one of these is set once a source is picked.
  String? _subSourceGroup; // bench sub card selected as source
  int? _subSourceSlot; // pitch starter selected as source
  // Target side: at most one is set once a target is chosen.
  String? _subPendingGroup;
  int? _subPendingSlot;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeBootstrap());
    // Load admin-configured card colours, then repaint so cards use them.
    CardTier.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    // Same fetch-once-then-repaint bootstrap for admin-configured ability
    // colours (AbilityMeta.of — see ability.dart) — drives the ability
    // draft/activation screens, the pitch/bench badges, the log, and help.
    AbilityMeta.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    // Same shape again for the admin-configured chemistry numbers
    // (ChemistryVars.resolve — see chemistry_vars.dart) that ability
    // descriptions and (in a later phase) other in-game text interpolate.
    // Without this, resolve() would only ever see its v1 fallback values,
    // never a live admin publish.
    ChemistryVars.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _gameLoadTimer?.cancel();
    super.dispose();
  }

  Future<void> _maybeBootstrap() async {
    if (!mounted) return;
    if (ref.read(gameProvider) != null) return;
    // Reconnect blank-state fix: a cold app restart into an in-progress
    // match goes HomeScreen (Jump In tap → jumpIn() sends check_presence,
    // opens a socket) → this screen, navigated the INSTANT room_update
    // arrives (room.isStarted is already true) — which can easily land
    // here BEFORE the separate, slightly-later game_state response for
    // that same check_presence has arrived. If roomProvider already has
    // state for this exact room, that connection is already live and
    // game_state is already on its way — calling jumpIn()/
    // jumpInAsSpectator() again here would call RoomSocketService.
    // reconnect(), which closes the socket and opens a brand new one,
    // discarding the very game_state response this screen is waiting for
    // and stranding the player on the loading spinner (an "effectively
    // empty" top-shell-only state) with nothing left to ever complete it.
    // Just wait for it on the connection that's already open instead of
    // tearing it down a second time.
    final existingRoom = ref.read(roomProvider);
    if (existingRoom != null && existingRoom.code == widget.roomCode) return;
    await ref.read(localPresenceProvider.notifier).ready;
    await ref.read(localSpectatorPresenceProvider.notifier).ready;
    if (!mounted) return;
    // Player presence always takes precedence — see room_provider.dart's
    // _savePresence, which actively clears spectator presence once a real
    // player seat is confirmed, so these two should never both legitimately
    // match this room at once. Still checked in this order defensively.
    final presence = ref.read(localPresenceProvider);
    if (presence != null && presence.roomCode == widget.roomCode) {
      ref.read(roomProvider.notifier).jumpIn();
      return;
    }
    final spectatorPresence = ref.read(localSpectatorPresenceProvider);
    if (spectatorPresence != null &&
        spectatorPresence.roomCode == widget.roomCode) {
      ref.read(roomProvider.notifier).jumpInAsSpectator();
      return;
    }
    context.goNamed(Routes.home);
  }

  // Returns the ordered list of player IDs: local player first, then others.
  List<String> _orderedPlayerIds(GameState game, String? localId) {
    final others = game.players
        .where((p) => p.id != localId)
        .map((p) => p.id)
        .toList();
    return [?localId, ...others];
  }

  // Clamp the tab index if a player leaves mid-game.
  int _safeTabIndex(int playerCount) =>
      _tabIndex.clamp(0, (playerCount - 1).clamp(0, 99));

  // ── Subs swap selection helpers ──────────────────────────────────────────

  UserSubstitutions? _readMySubs() {
    final localId = ref.read(localPlayerIdProvider);
    if (localId == null) return null;
    return ref.read(gameProvider)?.subsPhase?.userSubs[localId];
  }

  List<PitchSlot> _readMyPitchSlots() {
    final localId = ref.read(localPlayerIdProvider);
    if (localId == null) return const [];
    return ref.read(gameProvider)?.pitches[localId]?.slots ?? const [];
  }

  Iterable<(String, SubSlot)> _pickedSubs(UserSubstitutions s) sync* {
    if (s.att?.isPicked == true) yield ('att', s.att!);
    if (s.mid?.isPicked == true) yield ('mid', s.mid!);
    if (s.def?.isPicked == true) yield ('def', s.def!);
    if (s.extra?.isPicked == true) yield ('extra', s.extra!);
  }

  void _clearSubSelection() {
    setState(() {
      _subSourceGroup = null;
      _subSourceSlot = null;
      _subPendingGroup = null;
      _subPendingSlot = null;
    });
  }

  // Tap on a pitch starter during the subs phase. Free swapping: this card
  // becomes the source if none is selected, deselects if it's already the
  // source, otherwise it becomes the pending target for ANY current source
  // (bench→pitch or pitch→pitch). No position restriction — the only gate is
  // confirmation, which requires every starter to fit its slot (red ring).
  void _onSubsPitchSlotTap(PitchSlot slot) {
    // Only FILLED slots may participate in a swap — never an empty slot. (An
    // unpicked bench group is likewise unselectable, see _onSubsBenchTap.)
    if (!slot.isFilled) return;
    final mySubs = _readMySubs();
    if (mySubs == null) return;
    // Swapping is allowed throughout the subs phase (even while still picking
    // the remaining subs), so a player can rearrange their XI early — the
    // server (swapRoster) accepts any swap between filled slots before the
    // lineup is confirmed. Confirmation still requires all subs picked +
    // everyone in-position; that gate lives on the Confirm button, not here.

    if (_subSourceGroup == null && _subSourceSlot == null) {
      setState(() {
        _subSourceSlot = slot.index;
        _subPendingGroup = null;
        _subPendingSlot = null;
      });
      return;
    }
    if (_subSourceSlot == slot.index) {
      _clearSubSelection();
      return;
    }
    // Any other filled pitch slot is a valid target.
    setState(() {
      _subPendingSlot = slot.index;
      _subPendingGroup = null;
    });
  }

  // Tap on a bench sub card during the subs phase. Same free-swap rules as the
  // pitch: select as source, deselect, or become the pending target for ANY
  // source (pitch→bench or bench↔bench).
  void _onSubsBenchTap(String group) {
    final mySubs = _readMySubs();
    if (mySubs == null) return;
    final sub = switch (group) {
      'att' => mySubs.att,
      'mid' => mySubs.mid,
      'extra' => mySubs.extra,
      _ => mySubs.def,
    };
    if (sub?.isPicked != true) return;

    if (_subSourceGroup == null && _subSourceSlot == null) {
      setState(() {
        _subSourceGroup = group;
        _subPendingGroup = null;
        _subPendingSlot = null;
      });
      return;
    }
    if (_subSourceGroup == group) {
      _clearSubSelection();
      return;
    }
    // Any other picked bench sub is a valid target.
    setState(() {
      _subPendingGroup = group;
      _subPendingSlot = null;
    });
  }

  // All filled pitch slots except [exceptIndex] — every card is a free target.
  Set<int> _allOtherPitchTargets(int? exceptIndex) {
    final out = <int>{};
    for (final s in _readMyPitchSlots()) {
      if (!s.isFilled || s.index == exceptIndex) continue;
      out.add(s.index);
    }
    return out;
  }

  // All picked bench groups except [exceptGroup].
  Set<String> _allOtherBenchTargets(
    UserSubstitutions mySubs,
    String? exceptGroup,
  ) {
    final out = <String>{};
    for (final (group, _) in _pickedSubs(mySubs)) {
      if (group != exceptGroup) out.add(group);
    }
    return out;
  }

  // Builds the wire endpoint ({kind, index/group}) for a source/pending slot.
  Map<String, dynamic>? _endpoint({int? slotIndex, String? group}) {
    if (group != null) return {'kind': 'bench', 'group': group};
    if (slotIndex != null) return {'kind': 'pitch', 'index': slotIndex};
    return null;
  }

  void _applySubSwap() {
    final a = _endpoint(slotIndex: _subSourceSlot, group: _subSourceGroup);
    final b = _endpoint(slotIndex: _subPendingSlot, group: _subPendingGroup);
    if (a == null || b == null) return;
    ref.read(roomProvider.notifier).swapRoster(a, b);
    // Clear immediately — the swap result arrives via the game_state stream.
    _clearSubSelection();
  }

  /// The formation reveal plays once, only at the very start of the draft —
  /// round 1 with no cards placed yet — so it never replays on reconnect.
  bool _shouldRevealFormation(GameState game) {
    if (_formationRevealPlayed) return false;
    if (game.status != 'drafting' || game.currentRound != 1) return false;
    final anyPlaced = game.pitches.values.any((p) => p.filledCount > 0);
    return !anyPlaced;
  }

  @override
  Widget build(BuildContext context) {
    // ── Navigation listeners ───────────────────────────────────────────────

    ref.listen(gameProvider, (_, game) {
      // Any game_state arrival means the socket is healthy — hide reconnecting banner.
      if (game != null) {
        ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
      }
      if (game == null) return;
      if (!context.mounted) return;
      if (game.isFinished) {
        // In tournament mode, stay on the Tournament Hub so the player can
        // review the final standings and points, then tap "Go to Result"
        // themselves — don't yank them away the instant game_state(finished)
        // arrives (~3s after the champion is decided). The hub owns the CTA.
        _goToResult(game, respectTournamentHubStay: true);
      }
    });

    // Tournament mode: when the bracket-reveal phase begins, take over to the
    // Tournament Hub (only on the transition INTO bracketReveal) — OR, on a
    // reconnect landing directly inside an already-active tournament (any
    // phase, since bracket_reveal only ever lasts ~8s near the very start
    // and this listener's very first delivery — prev == null — would
    // otherwise never match the transition check below at all). Without the
    // second condition, a reconnecting client was stranded on GameScreen's
    // generic "Waiting for X…" fallback (game.status == 'tournament' isn't
    // handled by any of its phase branches) for the rest of the tournament,
    // with no ready button, no bracket, nothing actionable.
    ref.listen<TournamentStateModel?>(tournamentStateProvider, (prev, next) {
      if (next == null || !context.mounted) return;
      final enteringBracketReveal =
          prev?.phase != TournamentPhase.bracketReveal &&
          next.phase == TournamentPhase.bracketReveal;
      final reconnectingMidTournament =
          prev == null && ref.read(gameProvider)?.status == 'tournament';
      if (enteringBracketReveal || reconnectingMidTournament) {
        context.go('/game/${widget.roomCode}/tournament/bracket');
      }
    });

    // Show order-deck dialog the moment the prompt arrives (avoids sidebar layout issues).
    ref.listen(firstPlayerOrderProvider, (prev, next) {
      if (next == null || !context.mounted) return;
      // Only open if not already open (prev was null → next is not).
      if (prev != null) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => TacticalOrderSheet(
          prompt: next,
          onConfirm: (orderedIds) {
            Navigator.of(ctx).pop();
            ref
                .read(roomProvider.notifier)
                .orderHiddenDeck(next.turnId, orderedIds);
          },
        ),
      );
    });

    // Hidden-ability reveal: trigger the cinematic overlay exactly once, the
    // moment `abilityActivationRevealed` flips false→true WHILE this screen
    // is already live (`prev != null`). A reconnect's first-ever delivery
    // has `prev == null` by definition, so it can never fire here — that
    // client lands directly on the current (possibly already-resolved)
    // board via the normal panel/subs-phase rendering below, with no replay
    // attempted. See `_abilityRevealBatch`'s doc comment.
    ref.listen<GameState?>(gameProvider, (prev, next) {
      if (next == null) return;
      final justRevealed =
          prev != null &&
          prev.status == 'ability_activation' &&
          !prev.abilityActivationRevealed &&
          next.abilityActivationRevealed;
      if (justRevealed) {
        setState(() {
          _abilityRevealBatch = List.of(next.abilityActivations);
          _abilityRevealPlayers = List.of(next.players);
        });
      }

      // Hidden-pick reveal: fire once on the phase transition rather than
      // from _HiddenRevealPanel's build, which would replay it on every
      // rebuild the panel goes through while the phase is active.
      final justEnteredReveal =
          prev?.turn.phase != 'hidden_pick_reveal' &&
          next.turn.phase == 'hidden_pick_reveal';
      if (justEnteredReveal) {
        ref.read(audioServiceProvider).playSfx(Sfx.reveal);
      }

      // Card deal: a fresh turn's candidates land the moment this player
      // (any player, not just the locally active one — everyone sees the
      // same dealt row) enters card selection. Keyed on turnId rather than
      // "phase just became selecting_card" so it can't replay on an
      // unrelated rebuild while already in that phase.
      final justDealt =
          next.status == 'drafting' &&
          next.turn.phase == 'selecting_card' &&
          prev?.turn.turnId != next.turn.turnId;
      if (justDealt) {
        ref.read(audioServiceProvider).playSfx(Sfx.cardDeal);
      }
    });

    // Turn notification: a soft cue the moment it becomes this player's
    // turn — `prev == false` (not `!prev`) deliberately excludes the very
    // first delivery on load/reconnect, where `prev` is `null` and there is
    // nothing to "become" yet.
    ref.listen<bool>(isLocalPlayerTurnProvider, (prev, next) {
      if (next && prev == false) {
        ref.read(audioServiceProvider).playSfx(Sfx.notification);
      }
    });

    ref.listen(kickedProvider, (_, next) {
      next.whenData((_) {
        if (!context.mounted) return;
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            backgroundColor: HEColors.surfaceElevated,
            title: const Text('Removed from game'),
            content: const Text('The host has removed you from this room.'),
            actions: [
              TextButton(
                onPressed: () {
                  ref.read(roomProvider.notifier).clearAfterKick();
                  ref.read(gameProvider.notifier).reset();
                  Navigator.of(context).pop();
                  context.goNamed(Routes.home);
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      });
    });

    ref.listen(roomProvider, (_, room) {
      if (!mounted || room == null) return;
      if (!room.isStarted && ref.read(gameProvider) == null) {
        context.goNamed(Routes.lobby, pathParameters: {'roomCode': room.code});
      }
    });

    ref.listen(serverErrorProvider, (_, next) {
      next.whenData((err) {
        if (!mounted) return;
        if (err.code == 'NOT_FOUND' || err.code == 'INVALID_TOKEN') {
          // A rejected check_presence/spectator_reconnect. Previously
          // handled here directly, guarded on `roomProvider == null` — a
          // guard that's never true in exactly the case that matters (this
          // screen already mid-game, roomProvider non-null) and also raced
          // against RoomNotifier's own handling of the identical event on
          // the same underlying stream, since the two are independent
          // subscribers with no guaranteed ordering. Now handled centrally
          // and unconditionally by RoomNotifier._handleReconnectRejection,
          // which wipes all local room/game/presence state and triggers
          // sessionDesyncedProvider — HiddenElevenApp's root builder shows
          // the blocking SessionDesyncedScreen over every route the instant
          // that fires, so nothing further is needed here.
          return;
        }
        // Reachable draft/ability-draft errors previously had no feedback at
        // all — a rejected action (e.g. a double-tap racing the game_state
        // update that would have disabled the control, or a tap landing just
        // as a timer/reveal window advances the phase) just silently did
        // nothing, leaving the player staring at a control that looked
        // actionable but wasn't. Codes below are shared across pick_ability,
        // pick_slot, pick_card, order_hidden_deck, pick_hidden_slot, and
        // confirm_hidden_reveal — deliberately generic wording so one message
        // reads correctly no matter which of those requests actually failed.
        // Purely-defensive codes that no real UI action can trigger
        // (PITCH_NOT_FOUND, SLOT_NOT_FOUND, NO_ACTIVE_SLOT, SLOT_OUT_OF_RANGE)
        // are left unmapped on purpose — see SESSION_LOG.
        final message = switch (err.code) {
          'NOT_YOUR_TURN' => 'It\'s not your turn to pick yet.',
          'INVALID_CARD' =>
            'That card is already taken — pick a different one.',
          'NOT_ABILITY_DRAFT' => 'The ability draft has already moved on.',
          'WRONG_PHASE' || 'STALE_TURN' || 'GAME_NOT_DRAFTING' =>
            'The draft has already moved on — your view will refresh.',
          'SLOT_ALREADY_FILLED' ||
          'SLOT_ALREADY_TAKEN' ||
          'ROUND_SLOT_ALREADY_CHOSEN' =>
            'That was just taken — pick a different one.',
          'NOT_THE_PICKER' => 'Only the player who picked can continue.',
          'INVALID_ORDER_LENGTH' || 'INVALID_ORDER_IDS' =>
            'Something went wrong ordering the cards — please try again.',
          // activate_ability / discard_ability's own reachable codes — the
          // exact same silent-failure gap already fixed for the draft and
          // ability-draft phases, previously untouched for this one. A
          // double-tap racing the game_state update that would have
          // disabled the button, or a tap landing just as the phase's
          // auto-discard timer resolves everyone, both used to fail with
          // zero feedback.
          'NOT_ACTIVATION_PHASE' => 'The ability phase has already moved on.',
          'NO_PENDING_ABILITY' =>
            'You\'ve already used or discarded your card.',
          'INVALID_TARGET' => 'That\'s not a valid target — pick again.',
          'POSITION_MISMATCH' =>
            'You can only swap with a rival in the same position.',
          // pick_sub's one genuinely reachable error: two players can spin
          // independently and end up offered overlapping clubs, so a real
          // race to pick the same real player is possible — previously
          // silent (the spinner UI closes optimistically on tap, before the
          // server confirms, so by the time the rejection arrived nothing
          // was still listening for it). Other pick_sub/request_sub_spin
          // codes (SPIN_NOT_DONE, WRONG_POSITION_GROUP,
          // PLAYER_NOT_FROM_SPUN_CLUB, PLAYER_NOT_IN_POOL, PLAYER_NOT_FOUND,
          // NO_EXTRA_BENCH) aren't reachable through any real UI action —
          // the eligible-player list sent to the client is always already
          // filtered to the locked club/position/hasExtraBench, and
          // SUBS_ALREADY_COMPLETE/NOT_SUBS_PHASE are already handled by
          // SubsPanel's own dedicated spin-error listener.
          'PLAYER_ALREADY_USED' =>
            'That player was just taken — spin again or pick someone else.',
          // Lineup-rearrangement/confirm codes (swap_roster/swap_sub/
          // confirm_lineup). LINEUP_ALREADY_CONFIRMED/
          // ALREADY_CONFIRMED are two endpoints' own names for the same
          // "you already confirmed" race — genuinely reachable via the
          // subs-timer force-confirming everyone while a swap/confirm
          // request from this exact player was still in flight, or a fast
          // double-tap on Confirm before the first response updates the
          // locally-read confirmed flag (Confirm has no local optimistic
          // disable — it reads server truth on every rebuild). Other swap
          // codes (SAME_SLOT, SAME_ENDPOINT, SLOT_EMPTY, CARD_NOT_FOUND,
          // SUB_NOT_PICKED, STARTER_NOT_FOUND) aren't reachable through any
          // real UI action — the selection flow structurally can't pick the
          // same slot as both source and target, or target anything that
          // isn't already filled/picked. PLAYERS_OUT_OF_POSITION is mapped
          // anyway even though the Confirm button is already disabled
          // client-side whenever a starter is out of position (identical
          // cardFitsSlot logic on both sides) — defense in depth costs
          // nothing here.
          'LINEUP_ALREADY_CONFIRMED' ||
          'ALREADY_CONFIRMED' => 'Your lineup is already confirmed.',
          'PLAYERS_OUT_OF_POSITION' =>
            'Fix your out-of-position players before confirming.',
          _ => null,
        };
        if (message == null) return;
        ref.read(audioServiceProvider).playSfx(Sfx.invalidAction);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      });
    });

    ref.listen(socketDisconnectedProvider, (_, next) {
      next.whenData((_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            backgroundColor: HEColors.surfaceElevated,
            title: const Text('Connection lost'),
            content: const Text(
              'Could not reconnect to the server. You will be returned to the home screen.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  ref.read(roomProvider.notifier).exitGameToHome();
                  ref.read(gameProvider.notifier).reset();
                  Navigator.of(context).pop();
                  context.goNamed(Routes.home);
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      });
    });

    ref.listen(turnAutoPickedProvider, (_, next) {
      next.whenData((event) {
        if (!mounted) return;
        final localId = ref.read(localPlayerIdProvider);
        final isLocal = event.playerId == localId;
        // Falls back to the generic phrasing if the player has already left
        // game.players (shouldn't normally happen — the roster keeps
        // disconnected players until the game ends — but a missing name is
        // no reason to crash a snackbar).
        final timedOutName = ref
            .read(gameProvider)
            ?.players
            .where((p) => p.id == event.playerId)
            .firstOrNull
            ?.displayName;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              turnAutoPickedMessage(
                isLocal: isLocal,
                timedOutPlayerName: timedOutName,
              ),
            ),
            backgroundColor: isLocal
                ? const Color(0xFFE74C3C)
                : const Color(0xFF555555),
            duration: const Duration(seconds: 3),
          ),
        );
      });
    });

    ref.listen(socketReconnectingProvider, (_, next) {
      next.whenData((_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showMaterialBanner(
          MaterialBanner(
            backgroundColor: HEColors.surfaceElevated,
            leading: const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: HEColors.accent,
              ),
            ),
            content: const Text(
              'Reconnecting…',
              style: TextStyle(color: HEColors.textSecondary, fontSize: 13),
            ),
            actions: const [SizedBox.shrink()],
          ),
        );
      });
    });

    // ── State ──────────────────────────────────────────────────────────────

    final game = ref.watch(gameProvider);
    final localPlayerId = ref.watch(localPlayerIdProvider);
    // Explicit signal for "can this client take gameplay actions at all" —
    // deliberately separate from localPlayerId being null, so gating never
    // depends on identity-resolution edge cases (see SpectatorGate's docstring).
    final isSpectating = ref.watch(roomProvider)?.isSpectating ?? false;
    final isMyTurn = ref.watch(isLocalPlayerTurnProvider);
    // Always watch all phase providers so their notifiers stay subscribed.
    final candidates = ref.watch(slotCandidatesProvider);
    final orderPrompt = ref.watch(firstPlayerOrderProvider);
    final hiddenPickData = ref.watch(hiddenPickProvider);
    final revealedCard = ref.watch(revealedCardProvider);
    final turnTimer = ref.watch(turnTimerProvider);
    final connectionStatus = ref.watch(connectionStatusProvider);

    if (game == null) {
      // Re-armed on every build while there's no game to show; cancelled
      // the moment one arrives (see _watchForStuckLoad's doc comment).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _watchForStuckLoad();
      });
      return Scaffold(
        body: Center(
          child: _gameLoadTimedOut
              ? _StuckLoadingView(onRetry: _retryGameLoad)
              : const CircularProgressIndicator(),
        ),
      );
    }

    // Reconnecting directly into an already-finished match: the ref.listen
    // above only fires on a CHANGE, and there's no prior value to transition
    // FROM on this widget's very first build — a reconnect whose first-ever
    // game_state already has isFinished: true would otherwise never trigger
    // it, stranding the player on GameScreen forever (none of its phase
    // branches below handle a finished game either). Scoped to exactly the
    // FIRST game_state this widget ever observes (_sawFirstGameState) so a
    // match that finishes LATER, live, while this screen is already
    // mounted, is handled solely by the listener above — this check must
    // never re-fire on a later rebuild, or it would bypass that listener's
    // tournament-hub-stay exception every time (GameScreen stays mounted,
    // just backgrounded, under the nested tournament/bracket route).
    // Deliberately does NOT itself respect that exception — a reconnecting
    // client never received the one-off tournament_complete event the
    // exception depends on, and the Result screen already renders the full
    // tournament awards summary, so going straight there loses nothing a
    // fresh Hub visit would have shown.
    if (!_sawFirstGameState) {
      _sawFirstGameState = true;
      if (game.isFinished) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _goToResult(game, respectTournamentHubStay: false);
        });
      }
    }

    // Ability draft is a full-screen takeover before the normal player draft.
    // The formation reveal plays FIRST (once), then the card deck appears.
    if (game.status == 'ability_draft') {
      if (!_formationRevealPlayed) {
        return Scaffold(
          backgroundColor: HEColors.surface,
          body: SafeArea(
            child: FormationRevealOverlay(
              formationName: game.formationName,
              onDone: () => setState(() => _formationRevealPlayed = true),
            ),
          ),
        );
      }
      return SpectatorGate(
        isSpectating: isSpectating,
        child: AbilityDraftScreen(
          game: game,
          localPlayerId: localPlayerId,
          // Unlike every other phase, this screen is a full-screen takeover
          // that bypasses _ActionPanel entirely — so it never inherited
          // _ActionPanel's own connectionStatus gating. The top-level
          // "Reconnecting…"/"Connection lost" banner/dialog above already
          // makes the connection problem visible; this just makes sure a
          // card can't actually be tapped (and a pick sent into a socket
          // that may not survive) while it's showing.
          connected: connectionStatus == ConnectionStatus.connected,
        ),
      );
    }

    final orderedIds = _orderedPlayerIds(game, localPlayerId);
    final safeTab = _safeTabIndex(orderedIds.length);
    if (safeTab != _tabIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _tabIndex = safeTab);
      });
    }

    final viewedPlayerId = orderedIds.isNotEmpty ? orderedIds[safeTab] : null;
    final viewedPitch = viewedPlayerId != null
        ? game.pitches[viewedPlayerId]
        : null;
    final viewedSlots = viewedPitch?.slots ?? [];

    // Candidates are ready when they match the current turn.
    final candidatesReady =
        candidates != null &&
        candidates.turnId == game.turn.turnId &&
        isMyTurn &&
        game.turn.phase == 'selecting_card';

    // Active slot label for the candidate panel header.
    final activeSlot = game.turn.activeSlotIndex != null
        ? viewedSlots
              .where((s) => s.index == game.turn.activeSlotIndex)
              .firstOrNull
        : null;

    // ── Sub swap selection state ───────────────────────────────────────────
    // Always-shown amber set = pitch slots currently holding a swapped-in sub.
    // The rest (source / target highlights) derive from the local selection.
    Set<int> swappedSubSlots = const {};
    SubSwapView subSwap = SubSwapView.none;

    // Free-swap selection state (SubSwapView) is a lineup_edit-only concept
    // (Track B step 4) — bench_selection (step 2) never enters this branch.
    if (game.status == 'lineup_edit' && localPlayerId != null) {
      final mySubs = game.subsPhase?.userSubs[localPlayerId];
      final myPitchSlots = game.pitches[localPlayerId]?.slots ?? const [];
      if (mySubs != null && mySubs.lineupConfirmed != true) {
        final swapped = <int>{};
        for (final (_, sub) in _pickedSubs(mySubs)) {
          if (sub.isSwapped && sub.swappedSlotIndex != null) {
            swapped.add(sub.swappedSlotIndex!);
          }
        }
        swappedSubSlots = swapped;

        // Target highlight sets + labels, derived from the current source.
        Set<int> targetSlots = const {};
        Set<String> targetGroups = const {};
        String? sourceLabel;
        String? targetLabel;

        String? labelForGroup(String g) {
          final sub = switch (g) {
            'att' => mySubs.att,
            'mid' => mySubs.mid,
            'extra' => mySubs.extra,
            _ => mySubs.def,
          };
          if (sub == null) return null;
          // The bench always shows whatever card currently sits on it.
          final c = sub.benchCard;
          if (c != null) return '${c.playerName} (${c.basePositionType})';
          return '${sub.chosenPlayerName ?? '?'} (${sub.chosenPlayerPosition ?? '?'})';
        }

        String? labelForSlot(int idx) {
          final s = myPitchSlots.where((s) => s.index == idx).firstOrNull;
          if (s == null) return null;
          return '${s.cardPlayerName ?? '?'} (${s.label})';
        }

        // Free swapping: once a source is selected, EVERY other card (pitch or
        // bench) is a valid target. The red ring (out-of-position) is purely
        // advisory and only blocks confirmation, never the swap itself.
        if (_subSourceGroup != null) {
          targetSlots = _allOtherPitchTargets(null);
          targetGroups = _allOtherBenchTargets(mySubs, _subSourceGroup);
          sourceLabel = labelForGroup(_subSourceGroup!);
          if (_subPendingSlot != null) {
            targetLabel = labelForSlot(_subPendingSlot!);
          } else if (_subPendingGroup != null) {
            targetLabel = labelForGroup(_subPendingGroup!);
          }
        } else if (_subSourceSlot != null) {
          targetSlots = _allOtherPitchTargets(_subSourceSlot);
          targetGroups = _allOtherBenchTargets(mySubs, null);
          sourceLabel = labelForSlot(_subSourceSlot!);
          if (_subPendingGroup != null) {
            targetLabel = labelForGroup(_subPendingGroup!);
          } else if (_subPendingSlot != null) {
            targetLabel = labelForSlot(_subPendingSlot!);
          }
        }

        subSwap = SubSwapView(
          sourceGroup: _subSourceGroup,
          sourceSlotIndex: _subSourceSlot,
          targetGroups: targetGroups,
          targetSlots: targetSlots,
          pendingGroup: _subPendingGroup,
          pendingSlotIndex: _subPendingSlot,
          sourceLabel: sourceLabel,
          targetLabel: targetLabel,
        );
      }
    }

    // ── Responsive layout ──────────────────────────────────────────────────
    final layoutBuilder = LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        return isWide
            ? _WideLayout(
                game: game,
                orderedIds: orderedIds,
                localPlayerId: localPlayerId,
                isSpectating: isSpectating,
                connectionStatus: connectionStatus,
                viewedPlayerId: viewedPlayerId,
                viewedSlots: viewedSlots,
                isMyTurn: isMyTurn,
                candidatesReady: candidatesReady,
                candidates: candidates,
                orderPrompt: orderPrompt,
                hiddenPickData: hiddenPickData,
                activeSlot: activeSlot,
                tabIndex: safeTab,
                turnTimer: turnTimer,
                subSwap: subSwap,
                swappedSubSlots: swappedSubSlots,
                onSubsPitchSlotTap: _onSubsPitchSlotTap,
                onSubsBenchTap: _onSubsBenchTap,
                onSubsSwapPressed: _applySubSwap,
                onSubsCancelSelection: _clearSubSelection,
                onTabChanged: (i) => setState(() => _tabIndex = i),
                onSlotTap: (idx) => ref
                    .read(roomProvider.notifier)
                    .pickSlot(game.turn.turnId, idx),
                onCardPick: (cardId) {
                  final turnId = candidates?.turnId ?? game.turn.turnId;
                  ref.read(audioServiceProvider).playSfx(Sfx.pickCard);
                  // The wire call goes first and is never gated on the
                  // confirmation overlay below — turn order, the turn timer
                  // and multiplayer sync see exactly the same timing as
                  // before this reveal existed.
                  ref.read(roomProvider.notifier).pickCard(turnId, cardId);

                  // Presentation only: remember what was just signed so the
                  // player can see who they got and where they went.
                  final picked = candidates?.candidates
                      .where((c) => c.cardId == cardId)
                      .firstOrNull;
                  if (picked != null) {
                    _showCardAcquired(
                      picked,
                      activeSlot?.label ??
                          '${game.turn.activeSlotIndex ?? '?'}',
                      turnId,
                    );
                  }
                },
                onOrderConfirm: (orderedIds) => ref
                    .read(roomProvider.notifier)
                    .orderHiddenDeck(
                      orderPrompt?.turnId ?? game.turn.turnId,
                      orderedIds,
                    ),
                onHiddenSlotPick: (slotIndex) => ref
                    .read(roomProvider.notifier)
                    .pickHiddenSlot(
                      hiddenPickData?.turnId ?? game.turn.turnId,
                      slotIndex,
                    ),
                onConfirmReveal: () => ref
                    .read(roomProvider.notifier)
                    .confirmHiddenReveal(game.turn.turnId),
              )
            : _NarrowLayout(
                game: game,
                orderedIds: orderedIds,
                localPlayerId: localPlayerId,
                isSpectating: isSpectating,
                connectionStatus: connectionStatus,
                viewedPlayerId: viewedPlayerId,
                viewedSlots: viewedSlots,
                isMyTurn: isMyTurn,
                candidatesReady: candidatesReady,
                candidates: candidates,
                orderPrompt: orderPrompt,
                hiddenPickData: hiddenPickData,
                activeSlot: activeSlot,
                tabIndex: safeTab,
                turnTimer: turnTimer,
                subSwap: subSwap,
                swappedSubSlots: swappedSubSlots,
                onSubsPitchSlotTap: _onSubsPitchSlotTap,
                onSubsBenchTap: _onSubsBenchTap,
                onSubsSwapPressed: _applySubSwap,
                onSubsCancelSelection: _clearSubSelection,
                onTabChanged: (i) => setState(() => _tabIndex = i),
                onSlotTap: (idx) => ref
                    .read(roomProvider.notifier)
                    .pickSlot(game.turn.turnId, idx),
                onCardPick: (cardId) {
                  final turnId = candidates?.turnId ?? game.turn.turnId;
                  ref.read(audioServiceProvider).playSfx(Sfx.pickCard);
                  // The wire call goes first and is never gated on the
                  // confirmation overlay below — turn order, the turn timer
                  // and multiplayer sync see exactly the same timing as
                  // before this reveal existed.
                  ref.read(roomProvider.notifier).pickCard(turnId, cardId);

                  // Presentation only: remember what was just signed so the
                  // player can see who they got and where they went.
                  final picked = candidates?.candidates
                      .where((c) => c.cardId == cardId)
                      .firstOrNull;
                  if (picked != null) {
                    _showCardAcquired(
                      picked,
                      activeSlot?.label ??
                          '${game.turn.activeSlotIndex ?? '?'}',
                      turnId,
                    );
                  }
                },
                onOrderConfirm: (orderedIds) => ref
                    .read(roomProvider.notifier)
                    .orderHiddenDeck(
                      orderPrompt?.turnId ?? game.turn.turnId,
                      orderedIds,
                    ),
                onHiddenSlotPick: (slotIndex) => ref
                    .read(roomProvider.notifier)
                    .pickHiddenSlot(
                      hiddenPickData?.turnId ?? game.turn.turnId,
                      slotIndex,
                    ),
                onConfirmReveal: () => ref
                    .read(roomProvider.notifier)
                    .confirmHiddenReveal(game.turn.turnId),
              );
      },
    );

    // ── Night Tactics shell ────────────────────────────────────────────────
    //
    // The opaque AppBar is gone: it was the largest flat band on the screen
    // and was what made the arena background impossible to see. Everything
    // now floats over the arena inside one Stack, with the match bar as a
    // pill at the top carrying every responsibility the AppBar had.
    //
    // ArenaClock wraps BOTH the background and the foreground because they
    // share one ambient controller — the pitch's centre-circle sweep reads
    // it too — so the whole screen still runs exactly one looping animation.
    return Scaffold(
      backgroundColor: HETheme.pfBgVoid,
      body: ArenaClock(
        child: Stack(
          children: [
            Positioned.fill(
              child: ArenaBackground(
                layout: _arenaLayout(MediaQuery.sizeOf(context).width),
                // The background's half of the "one hot thing" rule: the
                // magenta mission field lights only when the local player
                // actually has something to do.
                missionActive: isMyTurn || _isParallelPhase(game.status),
              ),
            ),
            SideAdRail(
              slotId: AdConfig.gameSideSlot,
              child: SafeArea(
                child: Column(
                  children: [
                    _buildMatchBar(game),
                    if (isSpectating) const SpectatingBanner(),
                    // Reveal the cards no one picked last round (the "final" leftovers) —
                    // a compact chip, not a persistent full-width strip; tap to see them.
                    if (game.status == 'drafting' &&
                        game.lastRoundLeftovers.isNotEmpty)
                      _UnpickedChip(cards: game.lastRoundLeftovers),
                    Expanded(
                      child: Stack(
                        children: [
                          layoutBuilder,
                          // Card-flip reveal overlay — after a successful hidden pick.
                          if (revealedCard != null)
                            CardFlipReveal(
                              card: revealedCard,
                              // Tapping "continue" must actually continue.
                              // Dismissing only cleared the local overlay, so
                              // the game sat in `hidden_pick_reveal` until the
                              // server's 5s fallback advanced it — the tap
                              // appeared to do nothing. Confirming tells the
                              // server to move on straight away.
                              onDismiss: () {
                                ref
                                    .read(revealedCardProvider.notifier)
                                    .dismiss();
                                ref
                                    .read(roomProvider.notifier)
                                    .confirmHiddenReveal(game.turn.turnId);
                              },
                            ),
                          // Draft pick confirmation — who was just signed and
                          // which slot they filled. Non-blocking: it sits in
                          // the same overlay layer as the other reveals but
                          // is dismissible on tap, self-dismisses, and is
                          // force-cleared the moment the turn moves on (see
                          // the turnId guard below), so it can never sit over
                          // the next action.
                          if (_acquiredCard != null &&
                              _acquiredTurnId == game.turn.turnId)
                            Positioned.fill(
                              child: Center(
                                child: SingleChildScrollView(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: CardAcquiredReveal(
                                      card: _acquiredCard!,
                                      slotLabel: _acquiredSlotLabel ?? '',
                                      onDismiss: _clearCardAcquired,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          // Start-of-game formation reveal (plays once).
                          if (_shouldRevealFormation(game))
                            Positioned.fill(
                              child: FormationRevealOverlay(
                                formationName: game.formationName,
                                onDone: () => setState(
                                  () => _formationRevealPlayed = true,
                                ),
                              ),
                            ),
                          // Hidden-ability cinematic reveal — outlives the brief
                          // ability_activation → lineup_edit transition underneath it (see
                          // _abilityRevealBatch's doc comment).
                          if (_abilityRevealBatch != null &&
                              localPlayerId != null)
                            AbilityRevealOverlay(
                              activations: _abilityRevealBatch!,
                              players: _abilityRevealPlayers,
                              localPlayerId: localPlayerId,
                              onDone: () => setState(() {
                                _abilityRevealBatch = null;
                                _abilityRevealPlayers = const [];
                              }),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Which arena composition this viewport gets. Passed explicitly to
  /// [ArenaBackground] rather than re-derived there, so the background and
  /// the foreground can never disagree about which layout is on screen.
  ArenaLayout _arenaLayout(double width) {
    if (width < HETheme.breakpointMobile) return ArenaLayout.mobile;
    if (width < HETheme.breakpointTablet) return ArenaLayout.tablet;
    return ArenaLayout.desktop;
  }

  /// Post-draft phases are parallel for every seat — the local player always
  /// has work to do in them, regardless of whose draft turn it nominally is.
  /// Mirrors `MissionCard._isPostDraft` so the background's mission glow and
  /// the card's active state light up together.
  bool _isParallelPhase(String status) =>
      status == 'bench_selection' ||
      status == 'ability_activation' ||
      status == 'lineup_edit';

  /// The floating match bar. Carries every responsibility the old AppBar had
  /// — room code, formation, the auxiliary overflow menu, the persistent
  /// secret-ability reminder, and Leave — with identical callbacks and side
  /// effects. Nothing was dropped in the move off the AppBar.
  Widget _buildMatchBar(GameState game) {
    final isNarrow =
        MediaQuery.sizeOf(context).width < HETheme.breakpointMobile;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isNarrow ? 12 : 20,
        10,
        isNarrow ? 12 : 20,
        2,
      ),
      child: Align(
        alignment: isNarrow ? Alignment.center : Alignment.centerLeft,
        child: MatchBar(
          compact: isNarrow,
          roomCode: game.roomCode,
          formationName: game.formationName,
          menu: _buildOverflowMenu(game),
          // Persistent reminder of your secret ability card, all game.
          abilityChip: game.myAbility != null
              ? AbilityChip(type: game.myAbility!.type)
              : null,
          onLeave: () {
            ref.read(roomProvider.notifier).exitGameToHome();
            ref.read(gameProvider.notifier).reset();
            context.goNamed(Routes.home);
          },
        ),
      ),
    );
  }

  /// Help/history are pure auxiliary actions — none is needed to take a turn
  /// — so they stay collapsed into one overflow menu rather than sitting as
  /// 2-3 separate icons. AbilityChip stays direct: it's a reminder of owned
  /// secret game state, not help content.
  Widget _buildOverflowMenu(GameState game) {
    return PopupMenuButton<_GameMenuAction>(
      icon: const Icon(
        Icons.more_vert_rounded,
        color: HETheme.pfTextSecondary,
        size: 20,
      ),
      tooltip: 'More',
      color: HETheme.pfSurfaceGlass,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HEShape.rMd),
        side: const BorderSide(color: HETheme.arenaRim),
      ),
      onSelected: (action) {
        switch (action) {
          case _GameMenuAction.draftHelp:
            showContextHelp(
              context,
              contextKey: 'draft_scoring',
              title: 'Draft & Scoring',
              fallbackSections: _draftHelpSections,
            );
          case _GameMenuAction.abilitiesHelp:
            showAbilitiesHelpDialog(context);
          case _GameMenuAction.abilityLog:
            showAbilityLogDialog(context, game.abilityActivations, game: game);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _GameMenuAction.draftHelp,
          child: _MenuRow(
            icon: Icons.help_outline_rounded,
            label: 'Draft & Scoring Help',
          ),
        ),
        const PopupMenuItem(
          value: _GameMenuAction.abilitiesHelp,
          child: _MenuRow(
            icon: Icons.auto_awesome_rounded,
            label: 'How Abilities Work',
          ),
        ),
        if (game.abilityActivations.isNotEmpty)
          const PopupMenuItem(
            value: _GameMenuAction.abilityLog,
            child: _MenuRow(
              icon: Icons.history_rounded,
              label: 'Abilities Played',
            ),
          ),
      ],
    );
  }
}

// ── AppBar overflow menu ─────────────────────────────────────────────────────

enum _GameMenuAction { draftHelp, abilitiesHelp, abilityLog }

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: HEColors.textSecondary),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(color: HEColors.textPrimary, fontSize: 13),
        ),
      ],
    );
  }
}

// ── Spectating banner ──────────────────────────────────────────────────────
//
// Minimal, persistent (not dismissible) indicator that this client is a
// read-only observer — the only spectator UX this slice adds. Deliberately
// public so it's directly widget-testable, mirroring SpectatorList in
// lobby_screen.dart.
//
// Deliberately NOT magenta/emerald/amber/coral — those are reserved for
// "your turn now," "success/ready," "timer caution," and "danger/timeout"
// respectively (see he_theme.dart). Spectating is none of those states, so
// it renders in quiet lavender-on-violet instead — a viewer must never
// mistake this for an active-turn prompt or an error.
//
// A compact centered pill rather than the old full-width bar: it sits in
// the same Column slot, directly under the match bar, without claiming a
// full-width strip of vertical space above the pitch.
class SpectatingBanner extends StatelessWidget {
  const SpectatingBanner({super.key});

  static const _explanation =
      'You can follow the match live, but you cannot draft cards or change '
      'the lineup.';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Semantics(
          label: 'Spectating. $_explanation',
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: HETheme.pfSurfaceRaised.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(HEShape.rLg),
                  border: Border.all(
                    color: HETheme.pfSecondaryViolet.withValues(alpha: 0.55),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon in its own badge, not bare — the shape carries
                    // meaning too, not just the (already non-semantic)
                    // colour, per the "non-color-only indicator" requirement.
                    Container(
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.only(top: 1),
                      decoration: BoxDecoration(
                        color: HETheme.pfSecondaryViolet.withValues(
                          alpha: 0.25,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.visibility_rounded,
                        size: 13,
                        color: HETheme.pfLavenderText,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Spectating',
                            style: HETheme.body(
                              size: 12.5,
                              weight: FontWeight.w800,
                              color: HETheme.pfLavenderText,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            _explanation,
                            style: HETheme.body(
                              size: 10.5,
                              color: HETheme.pfTextMuted,
                            ).copyWith(height: 1.25),
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
      ),
    );
  }
}

// ── Stuck-loading recovery view ───────────────────────────────────────────────

/// Shown instead of an infinite spinner once _GameScreenState's stuck-load
/// timer fires — a successful room reconnect only proves the ROOM was
/// restored, not that the follow-up game_state message actually arrived.
/// Gives the player an explicit way out instead of a permanently frozen
/// loading screen.
class _StuckLoadingView extends StatelessWidget {
  const _StuckLoadingView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.hourglass_disabled_rounded,
            color: HEColors.textSecondary,
            size: 40,
          ),
          const SizedBox(height: 16),
          const Text(
            'Still trying to load your game…',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: HEColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'This is taking longer than expected. You can try again or '
            'return to the home screen.',
            textAlign: TextAlign.center,
            style: TextStyle(color: HEColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 24),
          HEButton(
            label: 'Retry',
            icon: Icons.refresh_rounded,
            onPressed: onRetry,
          ),
          const SizedBox(height: 8),
          HEButton(
            label: 'Return to Home',
            variant: HEButtonVariant.secondary,
            onPressed: () => context.goNamed(Routes.home),
          ),
        ],
      ),
    );
  }
}

// ── Leftover-cards chip (round-end reveal) ──────────────────────────────────

/// Compact entry point for the cards no one picked in the round that just
/// ended. This used to be a persistent full-width strip inline every round —
/// secondary, glanceable metadata that nonetheless competed with the pitch
/// and action panel for attention on every single turn. Now it's a small
/// tappable chip; the full list (still tap-to-details on every card) only
/// appears in a bottom sheet when asked for.
class _UnpickedChip extends StatelessWidget {
  const _UnpickedChip({required this.cards});
  final List<CandidateCard> cards;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _showLeftoversSheet(context, cards),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: HEColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: HEColors.accent.withValues(alpha: 0.30),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.local_fire_department_rounded,
                    color: HEColors.accent,
                    size: 13,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Unpicked (${cards.length})',
                    style: const TextStyle(
                      color: HEColors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.expand_more_rounded,
                    color: HEColors.accent.withValues(alpha: 0.75),
                    size: 16,
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

void _showLeftoversSheet(BuildContext context, List<CandidateCard> cards) {
  showDetailBottomSheet(
    context,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'UNPICKED LAST ROUND',
          style: TextStyle(
            color: HEColors.accent,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),
        // Full player cards (image, rating, name, club, flag, position) —
        // previously a plain 28px-thumbnail chip with just a name/rating
        // Row, which read as a weak list next to the proper cards used
        // everywhere else in the app. No PICK button: the round these
        // cards belonged to has already ended, they're historical, not
        // pickable — showCardDetailsModal still opens on tap for the full
        // stat breakdown.
        LayoutBuilder(
          builder: (ctx, box) {
            const gap = 10.0;
            const minCardW = 88.0;
            const maxCardW = 112.0;
            final cols = (box.maxWidth / (minCardW + gap)).floor().clamp(2, 4);
            final cardW = ((box.maxWidth - gap * (cols - 1)) / cols).clamp(
              minCardW,
              maxCardW,
            );
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: cards
                  .map(
                    (c) => SizedBox(
                      width: cardW,
                      child: PlayerCard(
                        card: c,
                        onTap: () => showCardDetailsModal(
                          ctx,
                          playerName: c.playerName,
                          rating: c.rating,
                          position: c.basePositionType,
                          imageSeed: c.cardId,
                          club: c.club,
                          clubLogoUrl: c.clubLogoUrl,
                          primaryColor: c.primaryColor,
                          secondaryColor: c.secondaryColor,
                          tertiaryColor: c.tertiaryColor,
                          kitPattern: c.kitPattern,
                          cardStyle: c.cardStyle,
                          kitNumber: c.kitNumber,
                          nationality: c.nationality,
                          altPositions: c.altPositions,
                          pace: c.pace,
                          shooting: c.shooting,
                          passing: c.passing,
                          dribbling: c.dribbling,
                          defending: c.defending,
                          physical: c.physical,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    ),
  );
}

// ── Formation reveal animation (start of game) ────────────────────────────────

/// Full-screen "slot machine" that cycles through formation names and lands on
/// the room's randomly-chosen formation with a pop, then fades out.
class FormationRevealOverlay extends StatefulWidget {
  const FormationRevealOverlay({
    super.key,
    required this.formationName,
    required this.onDone,
  });
  final String formationName;
  final VoidCallback onDone;

  @override
  State<FormationRevealOverlay> createState() => _FormationRevealOverlayState();
}

class _FormationRevealOverlayState extends State<FormationRevealOverlay>
    with TickerProviderStateMixin {
  static const _pool = <String>[
    '4-3-3',
    '4-4-2',
    '4-2-3-1',
    '3-5-2',
    '3-4-3',
    '5-3-2',
    '4-1-4-1',
    '4-5-1',
  ];

  late final AnimationController _intro;
  late final AnimationController _pop;
  late final AnimationController _outro;
  Timer? _cycleTimer;
  final _rng = Random();
  String _display = '4-3-3';
  bool _landed = false;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..forward();
    _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );
    _outro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _scheduleCycle(70, 0);
  }

  // Slot-machine cycling that decelerates, then lands on the real formation.
  void _scheduleCycle(int interval, int elapsed) {
    _cycleTimer = Timer(Duration(milliseconds: interval), () {
      if (!mounted) return;
      setState(() => _display = _pool[_rng.nextInt(_pool.length)]);
      final nextInterval = (interval * 1.16).round();
      final nextElapsed = elapsed + interval;
      if (nextElapsed < 1500 && nextInterval < 250) {
        _scheduleCycle(nextInterval, nextElapsed);
      } else {
        _land();
      }
    });
  }

  void _land() {
    setState(() {
      _display = widget.formationName;
      _landed = true;
    });
    _pop.forward();
    Future.delayed(const Duration(milliseconds: 1000), () async {
      if (!mounted) return;
      await _outro.forward();
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _cycleTimer?.cancel();
    _intro.dispose();
    _pop.dispose();
    _outro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_intro, _pop, _outro]),
      builder: (context, _) {
        final fadeIn = Curves.easeOut.transform(_intro.value);
        final fadeOut = 1.0 - _outro.value;
        final opacity = (fadeIn * fadeOut).clamp(0.0, 1.0);
        final pop = _landed ? Curves.elasticOut.transform(_pop.value) : 1.0;
        final scale = _landed ? (0.78 + 0.22 * pop) : 1.0;
        final color = _landed ? HEColors.accent : HEColors.textPrimary;
        return Opacity(
          opacity: opacity,
          child: Container(
            color: Colors.black.withValues(alpha: 0.86),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _landed ? 'YOUR FORMATION' : 'PICKING FORMATION',
                    style: TextStyle(
                      color: HEColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Transform.scale(
                    scale: scale,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: color.withValues(alpha: _landed ? 0.8 : 0.25),
                          width: 2,
                        ),
                        boxShadow: _landed
                            ? [
                                BoxShadow(
                                  color: HEColors.accent.withValues(
                                    alpha: 0.45,
                                  ),
                                  blurRadius: 28,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        _display,
                        style: TextStyle(
                          color: color,
                          fontSize: 48,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  AnimatedOpacity(
                    opacity: _landed ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 280),
                    child: Text(
                      'Locked in — draft your XI',
                      style: TextStyle(
                        color: HEColors.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Shared data bag passed to both layouts ─────────────────────────────────────

// ── Wide layout (≥ 720 px) ────────────────────────────────────────────────────

class _WideLayout extends StatelessWidget {
  const _WideLayout({
    required this.game,
    required this.orderedIds,
    required this.localPlayerId,
    required this.isSpectating,
    required this.connectionStatus,
    required this.viewedPlayerId,
    required this.viewedSlots,
    required this.isMyTurn,
    required this.candidatesReady,
    required this.candidates,
    required this.orderPrompt,
    required this.hiddenPickData,
    required this.activeSlot,
    required this.tabIndex,
    required this.turnTimer,
    required this.subSwap,
    required this.swappedSubSlots,
    required this.onSubsPitchSlotTap,
    required this.onSubsBenchTap,
    required this.onSubsSwapPressed,
    required this.onSubsCancelSelection,
    required this.onTabChanged,
    required this.onSlotTap,
    required this.onCardPick,
    required this.onOrderConfirm,
    required this.onHiddenSlotPick,
    required this.onConfirmReveal,
  });

  final GameState game;
  final List<String> orderedIds;
  final String? localPlayerId;

  /// Gates every gameplay-action tap in this layout via SpectatorGate — see
  /// its own docstring for why this is a separate signal from localPlayerId
  /// being null (identity vs. permission).
  final bool isSpectating;
  final ConnectionStatus connectionStatus;
  final String? viewedPlayerId;
  final List<PitchSlot> viewedSlots;
  final bool isMyTurn;
  final bool candidatesReady;
  final SlotCandidatesData? candidates;
  final FirstPlayerOrderData? orderPrompt;
  final HiddenPickData? hiddenPickData;
  final PitchSlot? activeSlot;
  final int tabIndex;
  final TurnTimerStarted? turnTimer;
  final SubSwapView subSwap;
  final Set<int> swappedSubSlots;
  final ValueChanged<PitchSlot> onSubsPitchSlotTap;
  final ValueChanged<String> onSubsBenchTap;
  final VoidCallback onSubsSwapPressed;
  final VoidCallback onSubsCancelSelection;
  final ValueChanged<int> onTabChanged;
  final ValueChanged<int> onSlotTap;
  final ValueChanged<String> onCardPick;
  final ValueChanged<List<String>> onOrderConfirm;
  final ValueChanged<int> onHiddenSlotPick;
  final VoidCallback onConfirmReveal;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, vp) {
        // All pitch/sidebar sizing lives in GameArenaMetrics — a pure value
        // type, so `game_layout_overflow_test.dart` can sweep real viewports
        // against the same code this builds from rather than a copy of the
        // formula. See that class for why the frame's cost must come from
        // ArenaFrame.totalInset and not from `bezel * 2`.
        final m = GameArenaMetrics.forViewport(
          vw: vp.maxWidth,
          // Body height: below the match bar, inside SafeArea.
          vh: vp.maxHeight,
        );
        final sidebarW = m.sidebarW;
        final pitchW = m.pitchW;
        final pitchH = m.pitchH;
        final needsScroll = m.needsScroll;

        // ── Build the left column ────────────────────────────────────────────
        final isViewingOwnPitchDuringSubs =
            game.status == 'lineup_edit' && viewedPlayerId == localPlayerId;

        final pitchWidget = PitchView(
          slots: viewedSlots,
          roundSlotIndex: game.currentRoundSlotIndex,
          isInteractiveOwner:
              viewedPlayerId == localPlayerId &&
              isMyTurn &&
              game.turn.phase == 'selecting_position',
          turnPhase: game.turn.phase,
          onSlotTap: onSlotTap,
          showChemistry: viewedPlayerId == localPlayerId,
          subsSourceSlotIndex: isViewingOwnPitchDuringSubs
              ? subSwap.sourceSlotIndex
              : null,
          subsTargetSlotIndices: isViewingOwnPitchDuringSubs
              ? subSwap.targetSlots
              : const {},
          subsPendingTargetIndex: isViewingOwnPitchDuringSubs
              ? subSwap.pendingSlotIndex
              : null,
          subsSwappedSlotIndices: isViewingOwnPitchDuringSubs
              ? swappedSubSlots
              : const {},
          subsSelectionActive: isViewingOwnPitchDuringSubs && subSwap.active,
          onSubsSlotTap: isViewingOwnPitchDuringSubs
              ? onSubsPitchSlotTap
              : null,
        );

        // Column content is the same whether or not we need scroll.
        // The pitch is wrapped in a SizedBox with explicit dimensions so
        // PitchView's internal AspectRatio receives tight constraints that
        // already satisfy the 0.625 ratio — it will use exactly pitchW × pitchH.
        //
        // Night Tactics: the pitch now sits inside a rim-lit ArenaFrame, and
        // the player tabs overlap that frame's top edge by _kTabOverlap. The
        // overlap is the cheapest real depth cue available and is most of
        // what stops the pitch reading as a flat image pasted on the page.
        // The arena block: the framed pitch with the player tabs overlapping
        // its top edge. The overlap is the cheapest real depth cue available
        // and is most of what stops the pitch reading as a flat image pasted
        // onto the page.
        final arenaBlock = SizedBox(
          // The frame's FULL cost — bezel AND border — read from
          // ArenaFrame.totalInset so this can never drift from _hChrome.
          width: pitchW + ArenaFrame.totalInset(_kArenaBezel),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: _kTabOverlap),
                child: ArenaFrame(
                  bezel: _kArenaBezel,
                  // Explicit dimensions so PitchView's internal AspectRatio
                  // receives tight constraints that already satisfy 0.625 —
                  // it uses exactly pitchW × pitchH and can never be squashed
                  // by a parent height constraint.
                  child: SizedBox(
                    width: pitchW,
                    height: pitchH,
                    child: pitchWidget,
                  ),
                ),
              ),
              Positioned(
                left: 8,
                right: 8,
                top: 0,
                child: SquadSwitcher(
                  tabs: buildSquadTabs(game, orderedIds, localPlayerId),
                  selectedIndex: tabIndex,
                  onChanged: onTabChanged,
                ),
              ),
            ],
          ),
        );

        final Widget leftColumn;
        if (needsScroll) {
          // Genuinely too short for a legible pitch: scroll rather than
          // shrink below the legibility floor. No Flexible here — inside a
          // scroll view the column's height is unbounded, so there is
          // nothing to flex against.
          leftColumn = SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: arenaBlock),
                const SizedBox(height: 16),
              ],
            ),
          );
        } else {
          leftColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Flexible is defence in depth, NOT the sizing mechanism: the
              // math above already guarantees the pitch fits. This exists so
              // that if a constant ever drifts again the pitch scales down
              // instead of overflowing — a slightly smaller pitch beats a red
              // overflow banner.
              Flexible(
                child: Center(child: ArenaEntrance(child: arenaBlock)),
              ),
              const SizedBox(height: 16),
            ],
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(
            // Stretch, not start: both columns need a bounded height so the
            // left column's Flexible guard and the sidebar's Expanded action
            // drawer have something real to flex against.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Left: pitch column ─────────────────────────────────────────
              Expanded(child: leftColumn),

              const SizedBox(width: 24),

              // ── Right: info + action column ────────────────────────────────
              //
              // No explicit height: it used to be pinned to `vh`, the FULL
              // viewport height, even though this sits inside a Padding that
              // has already consumed 32px vertically — a second latent
              // overflow of exactly that padding. The Row now stretches its
              // children, so this column gets precisely the height actually
              // available.
              SizedBox(
                width: sidebarW,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MissionCard(
                      currentRound: game.currentRound,
                      totalRounds: game.totalRounds,
                      turnPhase: game.turn.phase,
                      currentPlayer: game.currentPlayer,
                      isLocalPlayerTurn: isMyTurn,
                      gameStatus: game.status,
                      timerStartedAt:
                          turnTimer != null &&
                              turnTimer!.turnId == game.turn.turnId
                          ? turnTimer!.startedAt
                          : null,
                      timerDurationSeconds:
                          turnTimer != null &&
                              turnTimer!.turnId == game.turn.turnId
                          ? turnTimer!.turnDurationSeconds
                          : null,
                      onSettingsTap: () => showSettingsSheet(context),
                    ),
                    const SizedBox(height: 20),

                    // Phase-specific action panel — scrollable, fills remaining
                    // space. The individual phase panels (CandidatePanel,
                    // HiddenPickPanel, etc.) don't carry their own bordered
                    // card; this drawer supplies the single frame, so the
                    // sidebar keeps its "one boundary, not one per panel" look.
                    //
                    // Night Tactics: this is now an e2 floating drawer with a
                    // real gap above and below it, rather than a bordered box
                    // butted against the strip above. Those gaps are where the
                    // arena shows through — which is what stops this column
                    // reading as an admin dashboard.
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: HEElevation.e2(),
                              child: _ActionPanel(
                                game: game,
                                localPlayerId: localPlayerId ?? '',
                                isSpectating: isSpectating,
                                connectionStatus: connectionStatus,
                                isMyTurn: isMyTurn,
                                candidatesReady: candidatesReady,
                                candidates: candidates,
                                orderPrompt: orderPrompt,
                                hiddenPickData: hiddenPickData,
                                activeSlot: activeSlot,
                                onCardPick: onCardPick,
                                onOrderConfirm: onOrderConfirm,
                                onHiddenSlotPick: onHiddenSlotPick,
                                onConfirmReveal: onConfirmReveal,
                                subSwap: subSwap,
                                onSubsBenchTap: onSubsBenchTap,
                                onSubsSwapPressed: onSubsSwapPressed,
                                onSubsCancelSelection: onSubsCancelSelection,
                              ),
                            ),
                            // Private scoring preview — only shown to the local player.
                            // Collapsed to a summary bar by default; taps open the full
                            // breakdown in a bottom sheet instead of it sitting inline.
                            if (game.scoringPreview != null) ...[
                              const SizedBox(height: 16),
                              ScoringSummaryWithChips(
                                preview: game.scoringPreview!,
                              ),
                              const SizedBox(height: 10),
                              TeamChemistrySummary(
                                slots:
                                    game.pitches[localPlayerId]?.slots ??
                                    const [],
                                total: _chemistryTotal(game.scoringPreview!),
                              ),
                            ],
                            const SizedBox(height: 16),
                          ],
                        ),
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

/// Padding between the arena frame's outer edge and the pitch itself.
/// Callers must subtract `_kArenaBezel * 2` from the available box before
/// sizing the pitch — see `_WideLayout._hChrome`.
const double _kArenaBezel = GameArenaMetrics.kBezel;

/// How far the player tab pills stand proud of the arena frame's top edge.
/// The rest of their height sits over the frame, which is what produces the
/// layered depth cue.
const double _kTabOverlap = GameArenaMetrics.kTabOverlap;

// ── Narrow layout (< 720 px) ──────────────────────────────────────────────────

class _NarrowLayout extends StatelessWidget {
  const _NarrowLayout({
    required this.game,
    required this.orderedIds,
    required this.localPlayerId,
    required this.isSpectating,
    required this.connectionStatus,
    required this.viewedPlayerId,
    required this.viewedSlots,
    required this.isMyTurn,
    required this.candidatesReady,
    required this.candidates,
    required this.orderPrompt,
    required this.hiddenPickData,
    required this.activeSlot,
    required this.tabIndex,
    required this.turnTimer,
    required this.subSwap,
    required this.swappedSubSlots,
    required this.onSubsPitchSlotTap,
    required this.onSubsBenchTap,
    required this.onSubsSwapPressed,
    required this.onSubsCancelSelection,
    required this.onTabChanged,
    required this.onSlotTap,
    required this.onCardPick,
    required this.onOrderConfirm,
    required this.onHiddenSlotPick,
    required this.onConfirmReveal,
  });

  final GameState game;
  final List<String> orderedIds;
  final String? localPlayerId;

  /// See _WideLayout's identical field for why this is separate from
  /// localPlayerId being null.
  final bool isSpectating;
  final ConnectionStatus connectionStatus;
  final String? viewedPlayerId;
  final List<PitchSlot> viewedSlots;
  final bool isMyTurn;
  final bool candidatesReady;
  final SlotCandidatesData? candidates;
  final FirstPlayerOrderData? orderPrompt;
  final HiddenPickData? hiddenPickData;
  final PitchSlot? activeSlot;
  final int tabIndex;
  final TurnTimerStarted? turnTimer;
  final SubSwapView subSwap;
  final Set<int> swappedSubSlots;
  final ValueChanged<PitchSlot> onSubsPitchSlotTap;
  final ValueChanged<String> onSubsBenchTap;
  final VoidCallback onSubsSwapPressed;
  final VoidCallback onSubsCancelSelection;
  final ValueChanged<int> onTabChanged;
  final ValueChanged<int> onSlotTap;
  final ValueChanged<String> onCardPick;
  final ValueChanged<List<String>> onOrderConfirm;
  final ValueChanged<int> onHiddenSlotPick;
  final VoidCallback onConfirmReveal;

  // 3-zone mobile frame: status bar (natural height) → pitch stage (fills
  // whatever's left) → action sheet (capped, so it can never squeeze the
  // pitch away). Replaces the old single scrolling column of 5 stacked
  // regions — at most 3 things are ever on screen here at once.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: LayoutBuilder(
        builder: (context, box) {
          final vh = box.maxHeight;
          // The action sheet is capped well under half the body height, so
          // the pitch — the actual point of this screen — always keeps the
          // majority of the space regardless of how tall a phase's content
          // (e.g. the subs bench) gets; taller content just scrolls inside
          // the sheet instead of pushing the pitch off-screen.
          final sheetMaxH = (vh * 0.42).clamp(140.0, 380.0);
          // Reachable via the sheet's own expand handle when its default
          // content needs more room (a longer candidate list, or the same
          // content at a Large/XL text-size setting) — capped at 70% of the
          // available height rather than the full viewport specifically so
          // the pitch stage above it, still `Expanded`, is never squeezed to
          // nothing even at maximum expansion.
          final sheetExpandedMaxH = (vh * 0.70).clamp(320.0, 640.0);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MissionCard(
                currentRound: game.currentRound,
                totalRounds: game.totalRounds,
                turnPhase: game.turn.phase,
                currentPlayer: game.currentPlayer,
                isLocalPlayerTurn: isMyTurn,
                gameStatus: game.status,
                compact: true,
                timerStartedAt:
                    turnTimer != null && turnTimer!.turnId == game.turn.turnId
                    ? turnTimer!.startedAt
                    : null,
                timerDurationSeconds:
                    turnTimer != null && turnTimer!.turnId == game.turn.turnId
                    ? turnTimer!.turnDurationSeconds
                    : null,
                onSettingsTap: () => showSettingsSheet(context),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: GamePitchStage(
                  game: game,
                  orderedIds: orderedIds,
                  localPlayerId: localPlayerId,
                  viewedPlayerId: viewedPlayerId,
                  viewedSlots: viewedSlots,
                  isMyTurn: isMyTurn,
                  tabIndex: tabIndex,
                  subSwap: subSwap,
                  swappedSubSlots: swappedSubSlots,
                  onSubsPitchSlotTap: onSubsPitchSlotTap,
                  onTabChanged: onTabChanged,
                  onSlotTap: onSlotTap,
                ),
              ),
              GameActionSheet(
                compactMaxHeight: sheetMaxH,
                expandedMaxHeight: sheetExpandedMaxH,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ActionPanel(
                      game: game,
                      localPlayerId: localPlayerId ?? '',
                      isSpectating: isSpectating,
                      connectionStatus: connectionStatus,
                      isMyTurn: isMyTurn,
                      candidatesReady: candidatesReady,
                      candidates: candidates,
                      orderPrompt: orderPrompt,
                      hiddenPickData: hiddenPickData,
                      activeSlot: activeSlot,
                      onCardPick: onCardPick,
                      onOrderConfirm: onOrderConfirm,
                      onHiddenSlotPick: onHiddenSlotPick,
                      onConfirmReveal: onConfirmReveal,
                      subSwap: subSwap,
                      onSubsBenchTap: onSubsBenchTap,
                      onSubsSwapPressed: onSubsSwapPressed,
                      onSubsCancelSelection: onSubsCancelSelection,
                    ),
                    // Private scoring preview — only shown to the local
                    // player. Collapsed to a summary bar by default; taps
                    // open the full breakdown in a bottom sheet. Lives
                    // inside the action sheet as a minor trailing row, not
                    // a 4th major region of its own.
                    if (game.scoringPreview != null) ...[
                      const SizedBox(height: 12),
                      ScoringSummaryWithChips(preview: game.scoringPreview!),
                      const SizedBox(height: 10),
                      TeamChemistrySummary(
                        slots: game.pitches[localPlayerId]?.slots ?? const [],
                        total: _chemistryTotal(game.scoringPreview!),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Pitch stage (narrow layout middle zone) ───────────────────────────────────

/// The pitch stage: a slim, de-emphasized player-tab strip pinned to the top
/// and the pitch filling everything below it. This is the visual hero of the
/// narrow layout — it gets the `Expanded` remainder of the screen once the
/// status bar and action sheet have taken their (much smaller) share, sized
/// to fit both the available width and height so it's never cropped or
/// forced to scroll.
class GamePitchStage extends StatelessWidget {
  const GamePitchStage({
    super.key,
    required this.game,
    required this.orderedIds,
    required this.localPlayerId,
    required this.viewedPlayerId,
    required this.viewedSlots,
    required this.isMyTurn,
    required this.tabIndex,
    required this.subSwap,
    required this.swappedSubSlots,
    required this.onSubsPitchSlotTap,
    required this.onTabChanged,
    required this.onSlotTap,
  });

  final GameState game;
  final List<String> orderedIds;
  final String? localPlayerId;
  final String? viewedPlayerId;
  final List<PitchSlot> viewedSlots;
  final bool isMyTurn;
  final int tabIndex;
  final SubSwapView subSwap;
  final Set<int> swappedSubSlots;
  final ValueChanged<PitchSlot> onSubsPitchSlotTap;
  final ValueChanged<int> onTabChanged;
  final ValueChanged<int> onSlotTap;

  @override
  Widget build(BuildContext context) {
    final ownSubs =
        game.status == 'lineup_edit' && viewedPlayerId == localPlayerId;

    final pitchWidget = PitchView(
      slots: viewedSlots,
      roundSlotIndex: game.currentRoundSlotIndex,
      isInteractiveOwner:
          viewedPlayerId == localPlayerId &&
          isMyTurn &&
          game.turn.phase == 'selecting_position',
      turnPhase: game.turn.phase,
      onSlotTap: onSlotTap,
      showChemistry: viewedPlayerId == localPlayerId,
      subsSourceSlotIndex: ownSubs ? subSwap.sourceSlotIndex : null,
      subsTargetSlotIndices: ownSubs ? subSwap.targetSlots : const {},
      subsPendingTargetIndex: ownSubs ? subSwap.pendingSlotIndex : null,
      subsSwappedSlotIndices: ownSubs ? swappedSubSlots : const {},
      subsSelectionActive: ownSubs && subSwap.active,
      onSubsSlotTap: ownSubs ? onSubsPitchSlotTap : null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SquadSwitcher(
          tabs: buildSquadTabs(game, orderedIds, localPlayerId),
          selectedIndex: tabIndex,
          onChanged: onTabChanged,
          compact: true,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final availW = box.maxWidth;
              final availH = box.maxHeight.clamp(120.0, double.infinity);

              // The pitch is a fixed 0.625 (w:h) portrait. Fitting it purely
              // by height on a phone collapses its width to ~130px, at which
              // the 11 position cards overlap into an unreadable, un-tappable
              // cluster (the reported bug). So enforce a legibility FLOOR:
              // never render the pitch narrower than a width at which cards
              // stay readable and tappable. If the resulting height doesn't
              // fit, scroll vertically instead of shrinking — a portrait
              // pitch on a small phone genuinely can't show 11 legible cards
              // in one screenful, and a clear scroll beats an illegible blob.
              const minLegibleW = 300.0;
              // Floored to whole pixels before deriving the height, for the
              // same reason as the wide layout: a fractional width becomes a
              // fractional height that can round up past the available space.
              final heightFitW = (availH * 0.625).floorToDouble();
              final pitchW = min(availW, max(heightFitW, minLegibleW));
              final pitchH = (pitchW / 0.625).floorToDouble();

              // Whole pitch fits — centre it, no scroll (tall phones/tablets).
              //
              // No `+ 4` tolerance. Note this branch never *overflowed*: a
              // SizedBox taller than its parent's maxHeight silently resolves
              // to the parent's height, so the pitch quietly LOST its 0.625
              // ratio instead of erroring — a worse failure than a red
              // banner, because nothing surfaced it. Exact comparison plus
              // the scroll fallback below means the ratio always holds.
              if (pitchH <= availH) {
                return Center(
                  child: SizedBox(
                    width: pitchW,
                    height: pitchH,
                    child: pitchWidget,
                  ),
                );
              }
              // Too tall — vertical scroll keeps every card full-size and
              // tappable (critical for substitutions), instead of squeezing
              // them all into a height that makes them overlap.
              return SingleChildScrollView(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: SizedBox(
                      width: pitchW,
                      height: pitchH,
                      child: pitchWidget,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Phase-specific action panel ───────────────────────────────────────────────
// Shared by both wide and narrow layouts. Renders the correct widget for the
// current game phase and player context.

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.game,
    required this.localPlayerId,
    required this.isSpectating,
    required this.connectionStatus,
    required this.isMyTurn,
    required this.candidatesReady,
    required this.candidates,
    required this.orderPrompt,
    required this.hiddenPickData,
    required this.activeSlot,
    required this.onCardPick,
    required this.onOrderConfirm,
    required this.onHiddenSlotPick,
    required this.onConfirmReveal,
    required this.subSwap,
    required this.onSubsBenchTap,
    required this.onSubsSwapPressed,
    required this.onSubsCancelSelection,
  });

  final GameState game;
  final String localPlayerId;

  /// Every gameplay tap this panel can trigger (pick_ability, pick_card,
  /// order_hidden_deck, pick_hidden_slot, confirm_hidden_reveal, subs taps,
  /// confirm_lineup — everything SubsPanel/AbilityActivationPanel/
  /// CandidatePanel/etc. expose) is gated by this, via SpectatorGate wrapping
  /// the whole panel below. A single wrap point instead of touching every
  /// individual button in every one of those sub-widgets.
  final bool isSpectating;
  final ConnectionStatus connectionStatus;
  final bool isMyTurn;
  final bool candidatesReady;
  final SlotCandidatesData? candidates;
  final FirstPlayerOrderData? orderPrompt;
  final HiddenPickData? hiddenPickData;
  final PitchSlot? activeSlot;
  final ValueChanged<String> onCardPick;
  final ValueChanged<List<String>> onOrderConfirm;
  final ValueChanged<int> onHiddenSlotPick;
  final VoidCallback onConfirmReveal;
  final SubSwapView subSwap;
  final ValueChanged<String> onSubsBenchTap;
  final VoidCallback onSubsSwapPressed;
  final VoidCallback onSubsCancelSelection;

  @override
  Widget build(BuildContext context) {
    // Takes priority over every phase branch below, including the generic
    // waiting-for-another-player fallback at the end of _buildContent —
    // that fallback reads game.turn.activePlayerId/currentPlayer, which are
    // turn-based fields that mean nothing once the draft has ended (e.g.
    // during subs) and were the actual source of a lost connection getting
    // mistaken for "waiting for DFDF" instead of being shown as what it is.
    if (connectionStatus != ConnectionStatus.connected) {
      return PanelHeader(
        icon: Icons.wifi_off_rounded,
        eyebrow: 'CONNECTION',
        title: connectionStatus == ConnectionStatus.reconnecting
            ? 'Reconnecting… your progress will resume automatically'
            : 'Connection lost',
        emphasized: false,
      );
    }
    return SpectatorGate(
      isSpectating: isSpectating,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (gamePanelKindFor(game.status)) {
      // ── ability activation: use/discard your card (pitch stays visible) ────
      case GamePanelKind.abilityActivation:
        return AbilityActivationPanel(game: game, localPlayerId: localPlayerId);

      // ── bench_selection: choose 3 (att/mid/def) bench subs — Track B step 2 ─
      case GamePanelKind.benchSelection:
        return SubsPanel(
          game: game,
          localId: localPlayerId,
          mode: SubsPanelMode.benchSelection,
          // No swap/details/cancel wiring — bench_selection never enters a
          // swap-selection state (subSwap stays SubSwapView.none for this
          // status, see the subSwap computation above).
          connected: connectionStatus == ConnectionStatus.connected,
        );

      // ── lineup_edit: free swaps + confirmLineup — Track B step 4 ───────────
      case GamePanelKind.lineupEdit:
        return SubsPanel(
          game: game,
          localId: localPlayerId,
          mode: SubsPanelMode.lineupEdit,
          subSwap: subSwap,
          onBenchTap: onSubsBenchTap,
          onSwapPressed: onSubsSwapPressed,
          onCancelSelection: onSubsCancelSelection,
          // connectionStatus is already known == connected here (the check
          // above short-circuits otherwise), but SubsPanel takes it directly
          // as defense-in-depth rather than assuming its caller always gates
          // correctly.
          connected: connectionStatus == ConnectionStatus.connected,
        );

      case GamePanelKind.turnBased:
        break;
    }

    final phase = game.turn.phase;

    // ── selecting_card: active player has candidates ─────────────────────────
    if (phase == 'selecting_card' && candidatesReady && candidates != null) {
      final localPitch = game.pitches[localPlayerId];
      final lineupCards =
          localPitch?.slots
              .where((s) => s.isFilled)
              .map(LineupCard.fromSlot)
              .toList() ??
          const [];
      return CandidatePanel(
        candidates: candidates!.candidates,
        slotLabel: activeSlot?.label ?? '${game.turn.activeSlotIndex ?? '?'}',
        slotBasePosition: activeSlot?.basePositionType ?? '',
        onPick: onCardPick,
        lineup: lineupCards,
      );
    }

    // ── selecting_position: it's the local player's turn ────────────────────
    if ((phase == 'selecting_position' || phase == 'selecting_card') &&
        isMyTurn) {
      return _PickSlotPrompt(roundSlotIndex: game.currentRoundSlotIndex);
    }

    // ── first_player_order: dialog is shown via ref.listen in _GameScreenBody ─
    if (phase == 'first_player_order') {
      return WaitingBanner(
        message: isMyTurn
            ? 'Ordering the cards…'
            : 'Waiting for ${game.currentPlayer?.displayName ?? '—'} '
                  'to order the cards…',
      );
    }

    // ── hidden_pick_reveal: brief reveal window after a hidden pick ──────────
    // Only the reveal confirmation renders here — the picker grid behind it
    // added nothing a player needed mid-reveal and just competed for
    // attention with the actual "picked a card! / Continue" message.
    if (phase == 'hidden_pick_reveal') {
      final pickerName = game.players
          .where((p) => p.id == game.turn.revealPickerPlayerId)
          .map((p) => p.displayName)
          .firstOrNull;
      return _HiddenRevealPanel(
        isMyTurn: isMyTurn,
        pickerName: pickerName ?? '—',
        onContinue: onConfirmReveal,
      );
    }

    // ── hidden_pick: players pick blind ─────────────────────────────────────
    if (phase == 'hidden_pick') {
      final totalSlots = game.hiddenDeckSize;
      final takenSlots = game.hiddenSlotsTaken;
      final availableSlots = List.generate(
        totalSlots,
        (i) => i,
      ).where((i) => !takenSlots.contains(i)).toList();

      if (isMyTurn && hiddenPickData != null) {
        return HiddenPickPanel(
          // Keyed by turn id so the "magician" intro animation
          // (HiddenDraftIntro, inside HiddenPickPanel) plays exactly once
          // per hidden-pick turn: Flutter mounts fresh State (replaying the
          // intro) only when the server hands off to a genuinely new
          // turnId, while any other rebuild of this same turn — an
          // unrelated game_state update, a reconnect that resolves back
          // onto the still-current turn — reuses the existing State and
          // never replays mid-choice.
          key: ValueKey('hidden-pick-${hiddenPickData!.turnId}'),
          isActivePicker: true,
          totalSlots: hiddenPickData!.totalSlots,
          availableSlots: hiddenPickData!.availableSlots,
          slotMeta: game.hiddenSlots,
          previewCards: hiddenPickData!.previewCards,
          onPick: onHiddenSlotPick,
          onCardTap: (card) => _showHiddenCardDetails(context, card),
        );
      }
      return HiddenPickPanel(
        isActivePicker: false,
        totalSlots: totalSlots,
        availableSlots: availableSlots,
        slotMeta: game.hiddenSlots,
        waitingForName: game.currentPlayer?.displayName,
        onCardTap: (card) => _showHiddenCardDetails(context, card),
      );
    }

    // ── Fallback: waiting for another player ─────────────────────────────────
    // DraftStatusBar (Zone 1) already shows whose turn it is, so the dock
    // stays clean during wait — just a minimal row to avoid showing nothing.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: HEColors.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Waiting for ${game.currentPlayer?.displayName ?? '—'}…',
              style: const TextStyle(
                color: HEColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hidden card details helper ────────────────────────────────────────────────

void _showHiddenCardDetails(BuildContext context, CandidateCard card) {
  showCardDetailsModal(
    context,
    playerName: card.playerName,
    rating: card.rating,
    position: card.basePositionType,
    imageSeed: card.cardId,
    club: card.club,
    clubLogoUrl: card.clubLogoUrl,
    primaryColor: card.primaryColor,
    secondaryColor: card.secondaryColor,
    tertiaryColor: card.tertiaryColor,
    kitPattern: card.kitPattern,
    cardStyle: card.cardStyle,
    kitNumber: card.kitNumber,
    nationality: card.nationality,
    altPositions: card.altPositions,
    pace: card.pace,
    shooting: card.shooting,
    passing: card.passing,
    dribbling: card.dribbling,
    defending: card.defending,
    physical: card.physical,
    chemistryBonuses: card.chemistryBonuses,
  );
}

// ── Hidden reveal panel ────────────────────────────────────────────────────────

class _HiddenRevealPanel extends StatelessWidget {
  const _HiddenRevealPanel({
    required this.isMyTurn,
    required this.pickerName,
    required this.onContinue,
  });

  final bool isMyTurn;
  final String pickerName;
  final VoidCallback onContinue;

  // Renders bare — no border/background of its own — since it always
  // renders inside GameActionSheet/the sidebar frame, which already
  // supplies the one boundary around the sheet's content.
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$pickerName picked a card!',
          style: const TextStyle(
            color: HEColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        if (isMyTurn)
          HEButton(label: 'Continue', small: true, onPressed: onContinue)
        else
          // DraftStatusBar (Zone 1) already names whose turn it is.
          // Show only a minimal spinner rather than repeating the text.
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: HEColors.textSecondary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Pick-slot instruction prompt (wide layout, your turn, selecting_position) ──

/// Only renders for the "slot locked, candidates not in yet" loading window —
/// that's the one piece of information not shown anywhere else. The "tap a
/// position on the pitch" instruction used to be repeated here too, but the
/// Mission Card's turn row already states it and the pitch itself highlights
/// which slots are selectable, so showing it a third time here added noise
/// without adding information.
class _PickSlotPrompt extends StatelessWidget {
  const _PickSlotPrompt({required this.roundSlotIndex});
  final int? roundSlotIndex;

  // Renders bare — no border/background of its own — since it always
  // renders inside GameActionSheet/the sidebar frame. Uses the same
  // PanelHeader every other phase panel in the sheet uses.
  @override
  Widget build(BuildContext context) {
    final bool locked = roundSlotIndex != null;
    if (!locked) return const SizedBox.shrink();
    return const PanelHeader(
      icon: Icons.touch_app_rounded,
      eyebrow: 'SLOT LOCKED',
      title: 'Waiting for candidates…',
    );
  }
}
