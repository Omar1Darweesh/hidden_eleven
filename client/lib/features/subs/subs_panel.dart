import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/services/chemistry_evaluator.dart';
import 'package:hidden_eleven/features/game/widgets/ability_marker_badges.dart';
import 'package:hidden_eleven/features/game/widgets/card_details_modal.dart';
import 'package:hidden_eleven/features/game/widgets/panel_header.dart';
import 'package:hidden_eleven/features/game/widgets/player_card.dart';
// scoring_panel.dart intentionally not imported here — ScoringPanel is only
// ever shown via ScoringSummaryBar's bottom-sheet path (game_screen.dart).
// Importing it here and rendering it inline would duplicate the Squad Preview.
import 'package:hidden_eleven/features/lobby/models/server_event.dart';
import 'package:hidden_eleven/features/lobby/room_provider.dart';
import 'package:hidden_eleven/features/subs/club_roulette_drum.dart';
import 'package:hidden_eleven/features/subs/sub_swap_selection.dart';
import 'package:hidden_eleven/features/subs/subs_player_list.dart';
import 'package:hidden_eleven/shared/widgets/he_button.dart';

// Swap-flow state colors — centralized on HETheme.pf* so pitch_view.dart
// (the other half of the same swap UI) never drifts from these hues.
// Source-selected uses violet (a selection, not a success); pending target
// uses gold (a highlighted, about-to-commit choice); invalid uses danger.
const _kSelectViolet = HETheme.pfAccentViolet;
const _kValidTargetViolet = HETheme.pfAccentVioletGlow;
const _kPendingGold = HETheme.pfGold;
const _kInvalidRed = HETheme.pfDanger;

// ── Main panel ────────────────────────────────────────────────────────────────

/// Track B split: bench_selection (step 2 — att/mid/def spin+pick only, no
/// free-swap/confirm UI) vs lineup_edit (step 4 — free swaps, confirmLineup,
/// and Extra Bench's bonus 'extra' spin+pick). One panel, two render modes —
/// both phases share the same underlying [UserSubstitutions] data and most
/// of the same bench-group-card widgets, so a full split into two separate
/// widget classes would duplicate far more than it would clarify.
enum SubsPanelMode { benchSelection, lineupEdit }

class SubsPanel extends ConsumerStatefulWidget {
  const SubsPanel({
    super.key,
    required this.game,
    required this.localId,
    required this.mode,
    this.subSwap = SubSwapView.none,
    this.onBenchTap,
    this.onSwapPressed,
    this.onCancelSelection,
    this.connected = true,
  });
  final GameState game;
  final String localId;

  /// Which of Track B's two post-draft phases this panel is rendering for —
  /// see [SubsPanelMode].
  final SubsPanelMode mode;

  /// Current local swap selection (source/target/highlights).
  final SubSwapView subSwap;

  /// Called when a picked bench sub card is tapped (group key).
  final ValueChanged<String>? onBenchTap;

  /// Called when the [Swap] button is pressed.
  final VoidCallback? onSwapPressed;

  /// Called to clear the current selection.
  final VoidCallback? onCancelSelection;

  /// False while the socket is reconnecting/disconnected. Disables every
  /// action this panel can trigger (spin, pick, swap, cancel, confirm) so
  /// nothing fires into a connection that isn't confirmed healthy — the
  /// caller (_ActionPanel) already short-circuits to a connection message
  /// in this state, but this is defense-in-depth for any other caller.
  final bool connected;

  @override
  ConsumerState<SubsPanel> createState() => _SubsPanelState();
}

class _SubsPanelState extends ConsumerState<SubsPanel> {
  /// Locally cached full card data after each pick (for full PlayerCard display).
  CandidateCard? _attPickedCard;
  CandidateCard? _midPickedCard;
  CandidateCard? _defPickedCard;
  CandidateCard? _extraPickedCard;

  /// The local player's current starting XI as evaluation cards. Used to score
  /// each chemistry challenge (achieved vs remaining) in the details modal.
  List<LineupCard> _lineupCards() =>
      widget.game.pitches[widget.localId]?.slots
          .where((s) => s.isFilled)
          .map(LineupCard.fromSlot)
          .toList() ??
      const <LineupCard>[];

  // ── Inline spinner state ──────────────────────────────────────────────────
  // When [_spinGroup] is non-null the right-hand panel shows the club roulette +
  // player picker inline (beside the pitch) instead of a full-screen dialog, so
  // the lineup stays visible while choosing who to replace.
  String? _spinGroup;
  _ModalPhase _spinPhase = _ModalPhase.loading;
  SubSpinResult? _spinResult;

  void _startSpin(String group) {
    setState(() {
      _spinGroup = group;
      _spinPhase = _ModalPhase.loading;
      _spinResult = null;
    });
    debugPrint('[SubSpin] requesting spin for group=$group');
    ref.read(roomProvider.notifier).requestSubSpin(group);
  }

  void _onSpinResult(SubSpinResult result) {
    if (!mounted) return;
    if (result.positionGroup != _spinGroup) return;
    if (_spinPhase != _ModalPhase.loading) return;
    setState(() {
      _spinResult = result;
      _spinPhase = _ModalPhase.drum;
    });
  }

  // A pending request_sub_spin has no dedicated response — success arrives as
  // a sub_spin_result (handled above), failure arrives as a generic 'error'
  // event (e.g. SUBS_ALREADY_COMPLETE if the lineup was force-confirmed by a
  // subs-timeout — including a tournament's mid-transition window — while
  // this request was in flight). Without this handler the loading spinner
  // had nothing to catch that error: _spinGroup/_spinPhase just stayed stuck
  // on 'loading' forever, which is exactly the "can pick again but no cards
  // ever appear" symptom — the panel LOOKED reopenable but every request
  // silently died with no way back to the main dashboard short of leaving
  // and rejoining the room.
  void _onSpinError(String code) {
    if (!mounted) return;
    if (_spinGroup == null || _spinPhase != _ModalPhase.loading) return;
    setState(() {
      _spinGroup = null;
      _spinResult = null;
    });
    final message = switch (code) {
      'SUBS_ALREADY_COMPLETE' => 'Your lineup is already confirmed.',
      'NOT_SUBS_PHASE' => 'The substitutions phase has ended.',
      _ => 'Could not spin for a sub — please try again.',
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _onSpinPick(String group, CandidateCard card) {
    // Defensive two-frame split: this call lands in the same frame as the
    // details dialog's Navigator.pop() (its wrapping onPick pops first, then
    // calls this). Closing the spinner immediately (cheap) and deferring the
    // picked-card reveal (which builds a full PlayerCard) to the next frame
    // spreads that work across separate vsyncs rather than compositing the
    // dialog teardown and a fresh card in one. This is no longer load-bearing
    // for the emulator crash — that was the AspectRatio/IntrinsicHeight layout
    // issue, now fixed in _PickedSlot/PlayerCard — but it's a cheap, harmless
    // smoothing of the heaviest moment in the flow, so it stays.
    setState(() {
      _spinGroup = null;
      _spinResult = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        switch (group) {
          case 'att':
            _attPickedCard = card;
          case 'mid':
            _midPickedCard = card;
          case 'def':
            _defPickedCard = card;
          case 'extra':
            _extraPickedCard = card;
        }
      });
    });
    ref.read(roomProvider.notifier).pickSub(group, card.cardId);
  }

  // The full card data for the currently-selected swap source (bench sub or
  // pitch starter), used by the "View details" button.
  CandidateCard? _selectedSourceCard(UserSubstitutions? mySubs) {
    final sw = widget.subSwap;
    if (sw.sourceGroup != null) {
      final sub = switch (sw.sourceGroup) {
        'att' => mySubs?.att,
        'mid' => mySubs?.mid,
        _ => mySubs?.def,
      };
      return sub?.benchCard;
    }
    if (sw.sourceSlotIndex != null) {
      final slot = widget.game.pitches[widget.localId]?.slots
          .where((s) => s.index == sw.sourceSlotIndex)
          .firstOrNull;
      if (slot == null || !slot.isFilled) return null;
      // Show the card's OWN supported positions, not the slot's required one
      // (these differ when the starter is currently out of position).
      final nat = slot.effectiveNaturalPositions;
      final primary = nat.isNotEmpty ? nat.first : slot.basePositionType;
      return CandidateCard(
        cardId: slot.cardId ?? '',
        playerName: slot.cardPlayerName ?? '',
        basePositionType: primary,
        rating: slot.cardRating ?? 0,
        imageUrl: slot.cardImageUrl,
        club: slot.cardClub,
        clubLogoUrl: slot.cardClubLogoUrl,
        primaryColor: slot.cardPrimaryColor,
        secondaryColor: slot.cardSecondaryColor,
        tertiaryColor: slot.cardTertiaryColor,
        kitPattern: slot.cardKitPattern,
        cardStyle: slot.cardStyle,
        kitNumber: slot.cardKitNumber,
        nationality: slot.cardNationality,
        altPositions: nat.skip(1).toList(),
        naturalPositions: slot.effectiveNaturalPositions,
        pace: slot.cardPace,
        shooting: slot.cardShooting,
        passing: slot.cardPassing,
        dribbling: slot.cardDribbling,
        defending: slot.cardDefending,
        physical: slot.cardPhysical,
        chemistryBonuses: slot.cardChemistryBonuses,
      );
    }
    return null;
  }

  // Builds one bench group card with its current swap-selection state wired in.
  Widget _buildGroupCard(
    String group,
    String label,
    Color color,
    SubSlot? subSlot,
    CandidateCard? pickedCard,
    bool confirmed,
  ) {
    final sw = widget.subSwap;
    final selected = sw.sourceGroup == group;
    final pending = sw.pendingGroup == group;
    final isTarget = sw.targetGroups.contains(group) && !pending;
    final involved = selected || pending || isTarget;
    final dimmed = sw.active && !involved;
    final picked = subSlot?.isPicked == true;

    VoidCallback? onTap; // open the roulette modal (unpicked, idle)
    VoidCallback? onBenchTap; // selection tap (picked card)
    // Nothing in this panel fires while the connection isn't confirmed
    // healthy — see the `connected` field's doc comment.
    if (!confirmed && widget.connected) {
      // bench_selection: spin/pick only — the server rejects swapRoster
      // outright in this phase, so the tap target never becomes a swap
      // selector here regardless of `picked`.
      if (widget.mode == SubsPanelMode.benchSelection) {
        if (!picked) onTap = () => _startSpin(group);
      } else if (!picked) {
        // lineup_edit: att/mid/def are already picked by construction (bench
        // selection completed before this phase began) — an unpicked group
        // here can only be the 'extra' slot before Extra Bench's bonus spin
        // has been used yet, which still opens the spinner.
        if (!sw.active) onTap = () => _startSpin(group);
      } else {
        // A PICKED (filled) bench card is tappable for swapping throughout
        // lineup_edit — as a fresh source, or as a target for any current
        // source (including bench↔bench).
        onBenchTap = () => widget.onBenchTap?.call(group);
      }
    }

    // Whether the card currently on this bench was swapped in via a Sub card —
    // the swap badge follows the player here too.
    final benchCardId = (subSlot?.benchCard ?? pickedCard)?.cardId;
    final benchSwapped =
        benchCardId != null &&
        widget.game.subSwappedCardIds.contains(benchCardId);

    return _GroupSlotCard(
      label: label,
      color: color,
      subSlot: subSlot,
      pickedCard: pickedCard,
      confirmed: confirmed,
      selected: selected,
      isTarget: isTarget,
      pending: pending,
      dimmed: dimmed,
      onTap: onTap,
      onBenchTap: onBenchTap,
      lineup: _lineupCards(),
      benchSwapped: benchSwapped,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen for spin results to drive the inline spinner (loading → drum).
    ref.listen<AsyncValue<SubSpinResult>>(
      subSpinResultProvider,
      (_, next) => next.whenData(_onSpinResult),
    );
    // A rejected request_sub_spin (e.g. the lineup got force-confirmed by a
    // subs timeout while the request was in flight) has to be caught here
    // too, or the spinner hangs forever — see _onSpinError's doc comment.
    ref.listen<AsyncValue<ServerError>>(
      serverErrorProvider,
      (_, next) => next.whenData((e) => _onSpinError(e.code)),
    );

    // Inline spinner takes over the panel while active, keeping the pitch
    // (left column) visible so the player can see who they're replacing.
    if (_spinGroup != null) {
      return _InlineSpinnerView(
        label: _groupLabel(_spinGroup!),
        color: _groupColor(_spinGroup!),
        phase: _spinPhase,
        result: _spinResult,
        lineup: _lineupCards(),
        onDrumComplete: () =>
            setState(() => _spinPhase = _ModalPhase.playerList),
        onPick: (card) => _onSpinPick(_spinGroup!, card),
      );
    }

    final isBenchSelection = widget.mode == SubsPanelMode.benchSelection;
    final mySubs = widget.game.subsPhase?.userSubs[widget.localId];
    final allPicked = mySubs?.isComplete == true;
    // lineupConfirmed only ever means anything once lineup_edit begins —
    // bench_selection has no confirm step of its own (Track B step 5 is
    // lineup_edit-only), so treat it as never-confirmed while still on step 2.
    final confirmed = !isBenchSelection && mySubs?.lineupConfirmed == true;

    // A starter in a slot that doesn't match their primary/alt position blocks
    // confirmation. Count them so we can disable CONFIRM and show why.
    final mySlots = widget.game.pitches[widget.localId]?.slots ?? const [];
    final misplacedCount = mySlots
        .where((s) => s.isFilled && !s.cardFitsSlot)
        .length;
    final hasMisplaced = misplacedCount > 0;
    final canConfirm =
        allPicked && !confirmed && !hasMisplaced && widget.connected;

    if (allPicked && !confirmed) {
      debugPrint(
        '[SubsPanel] misplaced=$misplacedCount '
        'canSwap=${widget.subSwap.canSwap} '
        'source=${widget.subSwap.sourceLabel} '
        'target=${widget.subSwap.targetLabel}',
      );
    }

    final opponentEntries =
        widget.game.subsPhase?.userSubs.entries
            .where((e) => e.key != widget.localId)
            .toList() ??
        [];
    final opponentConfirmed =
        opponentEntries.isNotEmpty &&
        opponentEntries.every((e) => e.value.lineupConfirmed);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader(
          icon: isBenchSelection
              ? Icons.event_seat_rounded
              : Icons.swap_horiz_rounded,
          eyebrow: isBenchSelection ? 'BENCH SELECTION' : 'FINAL LINEUP',
          title: isBenchSelection
              ? (allPicked
                    ? 'Bench locked — next up: hidden tactical cards'
                    : 'Spin 3 bench players (ATK · MID · DEF). '
                          'When everyone is ready, abilities begin.')
              : mySubs?.hasExtraBench == true
              ? 'Abilities resolved — spin Extra Bench, then rearrange '
                    'and submit your final lineup'
              : 'Abilities resolved — rearrange your starting 11, '
                    'then submit your final lineup',
          emphasized: false,
        ),

        // Countdown — when the host set a subs time limit, the lineup is
        // auto-confirmed and the game ends when it hits zero.
        if (!confirmed && widget.game.subsDeadlineAtMs != null) ...[
          const SizedBox(height: 12),
          _SubsCountdown(deadlineMs: widget.game.subsDeadlineAtMs!),
        ],

        const SizedBox(height: 14),

        // Sub 1 (spun from the ATK pool, but freely swappable anywhere)
        _buildGroupCard(
          'att',
          'SUB 1',
          HETheme.pfPositionAttack,
          mySubs?.att,
          _attPickedCard,
          confirmed,
        ),
        const SizedBox(height: 8),

        // Sub 2 (spun from the MID pool)
        _buildGroupCard(
          'mid',
          'SUB 2',
          HETheme.pfPositionMid,
          mySubs?.mid,
          _midPickedCard,
          confirmed,
        ),
        const SizedBox(height: 8),

        // Sub 3 (spun from the DEF pool)
        _buildGroupCard(
          'def',
          'SUB 3',
          HETheme.pfPositionDef,
          mySubs?.def,
          _defPickedCard,
          confirmed,
        ),

        // Extra Bench sub (any position) — only during lineup_edit, and only
        // when the player has the card. hasExtraBench isn't known until
        // ability_activation resolves, which now runs strictly after
        // bench_selection — so this can never legitimately be true while
        // isBenchSelection is also true, but the explicit mode check keeps
        // that invariant defensive rather than implicit.
        if (!isBenchSelection && mySubs?.hasExtraBench == true) ...[
          const SizedBox(height: 8),
          _buildGroupCard(
            'extra',
            'EXTRA',
            HETheme.pfPositionExtra,
            mySubs?.extra,
            _extraPickedCard,
            confirmed,
          ),
        ],

        const SizedBox(height: 14),

        // Everything below this point — free swapping, the details/swap/
        // cancel buttons, the out-of-position warning, and confirmLineup —
        // is a lineup_edit-only mechanic (Track B step 4). bench_selection
        // (step 2) only spins/picks; it shows an explicit lock/wait status
        // instead (there is no separate lock RPC — the 3rd pick marks
        // isComplete and the server advances when the room is ready).
        if (isBenchSelection) ...[
          _BenchLockedStatus(
            allPickedLocally: allPicked,
            opponentAllPicked:
                opponentEntries.isNotEmpty &&
                opponentEntries.every((e) => e.value.isComplete),
            opponentCount: opponentEntries.length,
          ),
        ] else ...[
          // Swap action area: idle hint, "selected" prompt, or pending swap.
          // Available throughout lineup_edit (before confirm) — a player may
          // rearrange filled slots at any point, not only once Extra Bench's
          // bonus sub (if any) is picked. Two sub-states: source selected
          // (shows swap/cancel controls) or idle (shows the tap-to-start hint).
          if (!confirmed && widget.subSwap.hasSource)
            _SwapActionArea(subSwap: widget.subSwap)
          else if (!confirmed)
            const _SwapIdleHint(),

          // View-details button for the currently selected card (pitch or bench):
          // shows its supported positions and stats.
          if (!confirmed && widget.subSwap.hasSource) ...[
            Builder(
              builder: (context) {
                final src = _selectedSourceCard(mySubs);
                if (src == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: HEButton(
                    variant: HEButtonVariant.secondary,
                    small: true,
                    icon: Icons.info_outline,
                    label: 'Details: ${src.playerName}',
                    onPressed: () =>
                        _showCardDetails(context, src, lineup: _lineupCards()),
                  ),
                );
              },
            ),
          ],

          // Swap / Cancel — same shared HEButton every other primary/secondary
          // action in the sheet uses. Visible whenever a source is selected;
          // Swap enables only once a valid target is also chosen. Amber is
          // kept as the deliberate "pending action" color (matches the pitch's
          // own pending-target highlight) — HEButton's `color` override exists
          // specifically for state-specific cases like this one.
          //
          // Deliberately no speculative score preview for this pending,
          // unconfirmed selection — the score/chemistry impact only becomes
          // visible after the swap is confirmed and the server's fresh
          // scoringPreview arrives (ScoringSummaryBar animates the change).
          // Computing it here first would mean duplicating the server's
          // authoritative chemistry logic on the client — do not add that.
          if (!confirmed && widget.subSwap.hasSource) ...[
            HEButton(
              label: widget.subSwap.canSwap ? 'Swap' : 'Select a target',
              onPressed: widget.subSwap.canSwap && widget.connected
                  ? widget.onSwapPressed
                  : null,
              color: widget.subSwap.canSwap ? _kPendingGold : null,
            ),
            const SizedBox(height: 8),
            HEButton(
              variant: HEButtonVariant.secondary,
              small: true,
              label: 'Cancel',
              onPressed: widget.onCancelSelection,
            ),
          ],

          const SizedBox(height: 10),

          // Out-of-position warning — blocks confirmation until resolved. Shown
          // whenever a swap has left someone misplaced, even mid-choosing.
          if (!confirmed && hasMisplaced) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _kInvalidRed.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kInvalidRed.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.priority_high_rounded,
                    color: _kInvalidRed,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$misplacedCount player${misplacedCount == 1 ? '' : 's'} '
                      'out of position — fix the red card'
                      '${misplacedCount == 1 ? '' : 's'} to confirm.',
                      style: const TextStyle(
                        color: _kInvalidRed,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Final submit — distinct from bench-selection lock messaging.
          HEButton(
            label: confirmed
                ? 'Lineup Submitted ✓'
                : !allPicked
                ? 'Pick remaining bench slots first'
                : hasMisplaced
                ? 'Fix out-of-position players'
                : 'Submit Final Lineup',
            onPressed: canConfirm
                ? () => ref.read(roomProvider.notifier).confirmLineup()
                : null,
          ),

          const SizedBox(height: 8),

          _OpponentStatusRow(
            allPickedLocally: allPicked,
            localConfirmed: confirmed,
            opponentConfirmed: opponentConfirmed,
            opponentCount: opponentEntries.length,
          ),
        ],
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Color _groupColor(String group) => switch (group) {
  'att' => HETheme.pfPositionAttack,
  'mid' => HETheme.pfPositionMid,
  'extra' => HETheme.pfPositionExtra,
  _ => HETheme.pfPositionDef,
};

String _groupLabel(String group) => switch (group) {
  'att' => 'ATK',
  'mid' => 'MID',
  'extra' => 'ANY',
  _ => 'DEF',
};

// ── Group slot card ───────────────────────────────────────────────────────────

class _GroupSlotCard extends StatelessWidget {
  const _GroupSlotCard({
    required this.label,
    required this.color,
    required this.subSlot,
    required this.pickedCard,
    required this.confirmed,
    this.selected = false,
    this.isTarget = false,
    this.pending = false,
    this.dimmed = false,
    this.onTap,
    this.onBenchTap,
    this.lineup = const [],
    this.benchSwapped = false,
  });

  final String label;
  final Color color;
  final SubSlot? subSlot;
  final CandidateCard? pickedCard;
  final bool confirmed;
  final bool selected;
  final bool isTarget;
  final bool pending;
  final bool dimmed;
  final VoidCallback? onTap;
  final VoidCallback? onBenchTap;

  /// Local starting XI, threaded down so the bench card's details modal can show
  /// per-challenge chemistry progress.
  final List<LineupCard> lineup;

  /// True when the bench card was swapped in via a Sub card (shows swap badge).
  final bool benchSwapped;

  @override
  Widget build(BuildContext context) {
    final picked = subSlot?.isPicked == true;
    // A club can be locked (spun) with no player chosen yet — most commonly
    // after a reconnect mid-pick, since the club lock is durable server
    // state but re-tapping just re-opens the same locked club rather than
    // re-rolling. Previously this looked IDENTICAL to "never spun at all"
    // ("Tap to pick a sub" + a dice icon implying a fresh random spin),
    // which doesn't tell the player their club choice is already locked in.
    final clubLocked = !picked && subSlot?.spinResultClub != null;

    Widget child = picked
        ? _PickedSlot(
            label: label,
            color: color,
            slot: subSlot!,
            pickedCard: pickedCard,
            confirmed: confirmed,
            lineup: lineup,
            benchSwapped: benchSwapped,
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  // Left accent strip — group colour without a full border
                  Container(
                    width: 5,
                    height: double.infinity,
                    color: color.withValues(alpha: 0.70),
                  ),
                  const SizedBox(width: 12),
                  _LabelTab(label: label, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      confirmed
                          ? 'Lineup confirmed'
                          : clubLocked
                          ? '${subSlot!.spinResultClub} — pick a player'
                          : 'Tap to pick a sub',
                      style: const TextStyle(
                        color: HETheme.pfTextSecondary,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!confirmed)
                    Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: Icon(
                        clubLocked
                            ? Icons.group_outlined
                            : Icons.casino_outlined,
                        color: color,
                        size: 22,
                      ),
                    ),
                ],
              ),
            ),
          );

    // Selection ring: source = solid violet, pending target = gold
    // (highlighted, about to commit), valid unselected target = lighter
    // violet-glow — distinct from source without relying on brightness alone
    // (the icon/label content beside each ring also differs; see below).
    if (selected || pending || isTarget) {
      final ring = selected
          ? _kSelectViolet
          : pending
          ? _kPendingGold
          : _kValidTargetViolet;
      child = Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ring, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: ring.withValues(alpha: 0.45),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: child,
      );
    }

    if (dimmed) child = Opacity(opacity: 0.4, child: child);

    final tap = picked ? onBenchTap : onTap;
    if (tap == null) return child;
    return GestureDetector(onTap: tap, child: child);
  }
}

// ── Picked slot ───────────────────────────────────────────────────────────────

class _PickedSlot extends StatelessWidget {
  const _PickedSlot({
    required this.label,
    required this.color,
    required this.slot,
    required this.pickedCard,
    required this.confirmed,
    this.lineup = const [],
    this.benchSwapped = false,
  });

  final String label;
  final Color color;
  final SubSlot slot;
  final CandidateCard? pickedCard;
  final bool confirmed;
  final List<LineupCard> lineup;
  final bool benchSwapped;

  @override
  Widget build(BuildContext context) {
    // The card physically on the bench right now: from the server snapshot
    // (slot.benchCard) when available, otherwise the locally-cached pick.
    final benchCard = slot.benchCard ?? pickedCard;
    final holdsStarter = slot.benchHoldsStarter;
    // No full border on the picked slot — the parent action dock already
    // provides the visual boundary. Use clip + subtle tint only so
    // the selection ring (added by _GroupSlotCard) is the ONLY ring.
    // ── ANR FIX (Android emulator, picked bench render site) ──────────────
    // This subtree previously used IntrinsicHeight → Row → [accent strip with
    // height:double.infinity, Expanded(card)]. IntrinsicHeight forces an extra
    // intrinsic-sizing layout pass over its whole child subtree, and the card
    // below (PlayerCard, via AspectRatio) does not compose cleanly with that
    // pass. The combination hung the main thread on the Android emulator's
    // Impeller/OpenGLES backend — an ANR (SIGQUIT → tombstone), NOT a paint
    // crash — reproduced right after "post-frame: revealing picked card".
    // Bisection confirmed it: a fixed-size placeholder rendered fine here, but
    // reintroducing the AspectRatio-based card structure (with NO images/
    // gradient/shadow — "Stage B") re-froze it, isolating the trigger to the
    // IntrinsicHeight + AspectRatio structural interaction at THIS site.
    //
    // Fix: (1) drop IntrinsicHeight entirely; (2) render the left accent as a
    // decoration Border instead of a full-height stretching child — a border
    // paints to the container's naturally-resolved height with no intrinsic
    // pass and no double.infinity; (3) the card itself now takes an explicit
    // fixed width/height instead of AspectRatio (see _FullCardRow /
    // _StagedBenchCard). The Container now sizes tightly to its child's own
    // (bounded, deterministic) height, so nothing demands infinite height and
    // no intrinsic walk ever runs.
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          // Left accent: was a stretching child under IntrinsicHeight; now a
          // border that draws the full resolved height for free.
          border: Border(
            left: BorderSide(color: color.withValues(alpha: 0.65), width: 5),
          ),
        ),
        constraints: const BoxConstraints(minHeight: 64),
        child: benchCard != null
            ? _FullCardRow(
                label: label,
                color: color,
                card: benchCard,
                swapped: holdsStarter,
                subSwapped: benchSwapped,
                captain: slot.benchedCaptain,
                redCarded: slot.benchedRedCarded,
                coached: slot.benchedCoached,
                onInfo: () =>
                    _showCardDetails(context, benchCard, lineup: lineup),
              )
            : _CompactPickedRow(
                label: label,
                color: color,
                slot: slot,
                swapped: false,
              ),
      ),
    );
  }
}

class _FullCardRow extends StatelessWidget {
  const _FullCardRow({
    required this.label,
    required this.color,
    required this.card,
    required this.swapped,
    this.subSwapped = false,
    this.captain = false,
    this.redCarded = false,
    this.coached = false,
    this.onInfo,
  });

  final String label;
  final Color color;
  final CandidateCard card;
  final bool swapped;

  /// True when this bench card was swapped in via a Sub ability (shows badge).
  final bool subSwapped;

  /// True when this bench card was given an extra position by a Coach card —
  /// same purple whistle badge as a coached starter on the pitch (see
  /// PitchSlot.isCoached / pitch_view.dart).
  final bool coached;

  /// True when this bench card is captained — same visual treatment (gold
  /// armband) as a captained starter on the pitch (see PitchSlot.isCaptain /
  /// pitch_view.dart's identical badge, both sourced from
  /// ability_marker_badges.dart).
  final bool captain;

  /// True when this bench card was red-carded — same visual treatment (red
  /// wash + icon badge) as a red-carded starter on the pitch (see
  /// PitchSlot.isRedCarded).
  final bool redCarded;

  /// Opens the card-details sheet (positions, stats). Tapping the ⓘ button does
  /// NOT trigger swap selection — only the card body does.
  final VoidCallback? onInfo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Icon(
                  swapped ? Icons.swap_vert : Icons.check,
                  color: color,
                  size: 13,
                ),
                if (onInfo != null) ...[
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: onInfo,
                    child: Icon(
                      Icons.info_outline,
                      color: HETheme.pfTextSecondary,
                      size: 16,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Picked bench card render site ─────────────────────────────
              // Uses an EXPLICIT fixed width/height (_kBenchCardW ×
              // _kBenchCardH), NOT a width-only box. This is load-bearing: the
              // combination of PlayerCard's AspectRatio and _PickedSlot's old
              // IntrinsicHeight hung the Android emulator's renderer (ANR) at
              // this exact site. Both hazards are now removed — _PickedSlot no
              // longer uses IntrinsicHeight, and PlayerCard skips AspectRatio
              // when given a definite box (both axes bounded, which this
              // SizedBox provides). Do NOT revert to a width-only SizedBox and
              // do NOT wrap this in IntrinsicHeight. RepaintBoundary isolates
              // this card's shadow/gradient/image compositing into its own
              // layer.
              Stack(
                clipBehavior: Clip.none,
                children: [
                  SizedBox(
                    width: _kBenchCardW,
                    height: _kBenchCardH,
                    child: RepaintBoundary(
                      child: Stack(
                        children: [
                          PlayerCard(card: card),
                          if (redCarded)
                            const Positioned.fill(child: RedCardWashOverlay()),
                          // Coach highlight: a card-level purple outer ring +
                          // glow (not another small badge — see
                          // CoachedCardHighlight's doc comment) matching
                          // PlayerCard's own 12px corner radius.
                          if (coached)
                            const Positioned.fill(
                              child: CoachedCardHighlight(borderRadius: 12),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (redCarded)
                    const Positioned(
                      top: 3,
                      left: 3,
                      child: RedCardIconBadge(),
                    ),
                  if (subSwapped)
                    const Positioned(
                      bottom: -3,
                      left: -3,
                      child: SubSwapBadge(),
                    ),
                  if (captain)
                    const Positioned(
                      bottom: -3,
                      right: -3,
                      child: CaptainArmbandBadge(),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: _kBenchCardW,
                child: _AllowedPositionsLine(card: card),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Explicit picked-bench card footprint. 90 : 126 ≈ 3 : 4.2 (PlayerCard's
// aspect), but pre-computed as fixed numbers so NOTHING at the picked-bench
// site ever runs an AspectRatio resolution or an IntrinsicHeight pass — the
// combination that hung the Android emulator (see _PickedSlot's comment).
const double _kBenchCardW = 90;
const double _kBenchCardH = 126;

/// One-line list of every position a card can play (primary + alternates), for
/// a quick read without opening the details sheet. e.g. "CB · LB · RB".
class _AllowedPositionsLine extends StatelessWidget {
  const _AllowedPositionsLine({required this.card});
  final CandidateCard card;

  @override
  Widget build(BuildContext context) {
    final positions = <String>[
      card.basePositionType,
      ...card.altPositions.where((p) => p != card.basePositionType),
    ];
    return Text(
      positions.join(' · '),
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: HETheme.pfTextSecondary,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    );
  }
}

/// Self-ticking countdown banner for the subs phase. When it reaches zero the
/// server auto-confirms every lineup and ends the game (the client navigates to
/// results via the normal isFinished path), so this widget is display-only.
class _SubsCountdown extends StatefulWidget {
  const _SubsCountdown({required this.deadlineMs});
  final int deadlineMs;

  @override
  State<_SubsCountdown> createState() => _SubsCountdownState();
}

class _SubsCountdownState extends State<_SubsCountdown> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.deadlineMs - DateTime.now().millisecondsSinceEpoch;
    final secs = (remaining / 1000).ceil().clamp(0, 86400);
    final mm = (secs ~/ 60).toString().padLeft(2, '0');
    final ss = (secs % 60).toString().padLeft(2, '0');
    final urgent = secs <= 15;
    final color = urgent ? _kInvalidRed : HETheme.pfAccentViolet;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.hourglass_bottom_rounded, color: color, size: 16),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Time left to finish your lineup',
              style: TextStyle(color: HETheme.pfTextSecondary, fontSize: 11.5),
            ),
          ),
          Text(
            '$mm:$ss',
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the player-details sheet for a sub/bench [card] (positions + stats +
/// per-challenge chemistry progress). [lineup] is the player's current starting
/// XI, used to evaluate which of the card's challenges are achieved vs remaining.
void _showCardDetails(
  BuildContext context,
  CandidateCard card, {
  List<LineupCard> lineup = const [],
}) {
  showCardDetailsModal(
    context,
    playerName: card.playerName,
    rating: card.rating,
    position: card.primaryPosition,
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
    altPositions: card.naturalAltPositions,
    pace: card.pace,
    shooting: card.shooting,
    passing: card.passing,
    dribbling: card.dribbling,
    defending: card.defending,
    physical: card.physical,
    chemistryBonuses: card.chemistryBonuses,
    lineup: lineup,
  );
}

class _CompactPickedRow extends StatelessWidget {
  const _CompactPickedRow({
    required this.label,
    required this.color,
    required this.slot,
    required this.swapped,
  });

  final String label;
  final Color color;
  final SubSlot slot;
  final bool swapped;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Row(
        children: [
          Container(
            width: 48,
            height: double.infinity,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(9),
                bottomLeft: Radius.circular(9),
              ),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Icon(Icons.check, color: color, size: 14),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slot.chosenPlayerName ?? '',
                  style: const TextStyle(
                    color: HETheme.pfTextPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  slot.spinResultClub ?? '',
                  style: const TextStyle(
                    color: HETheme.pfTextSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${slot.chosenPlayerRating ?? ''}',
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  slot.chosenPlayerPosition ?? '',
                  style: const TextStyle(
                    color: HETheme.pfTextMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Inline spinner (club roulette + player picker, hosted in the side panel) ──

enum _ModalPhase { loading, drum, playerList }

/// Renders the sub spin/pick flow inline within the subs panel (beside the
/// pitch) instead of a full-screen dialog, so the lineup stays visible while
/// the player chooses who to bring on. State (phase/result) lives in
/// [_SubsPanelState]; this widget is purely presentational.
class _InlineSpinnerView extends StatelessWidget {
  const _InlineSpinnerView({
    required this.label,
    required this.color,
    required this.phase,
    required this.result,
    required this.lineup,
    required this.onDrumComplete,
    required this.onPick,
  });

  final String label;
  final Color color;
  final _ModalPhase phase;
  final SubSpinResult? result;
  final List<LineupCard> lineup;
  final VoidCallback onDrumComplete;
  final void Function(CandidateCard) onPick;

  @override
  Widget build(BuildContext context) {
    // Cap the height of the fixed-size loading/drum phases so they never
    // overflow the action dock. ClubRouletteDrum (72px itemExtent × 3 visible
    // rows + its own club-name label row) is 243px tall; 336px leaves real
    // margin plus headroom for larger accessibility text-scale settings.
    //
    // The player-list phase is deliberately NOT capped here — see _body()'s
    // usage below. It renders inline and is scrolled by the single ancestor
    // scroll region (the mobile GameActionSheet's SingleChildScrollView, or
    // the wide sidebar's). Capping it would re-create a height-limited,
    // nested inner scroll area that contested drag gestures with that
    // ancestor — the exact mobile "can't scroll the candidate list" bug.
    const double maxBodyH = 336.0;

    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header — group tag + back/close button.
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
            color: Color.alphaBlend(
              color.withValues(alpha: 0.10),
              HETheme.pfSurfaceRaised,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'PICK A SUBSTITUTE',
                    style: TextStyle(
                      color: HETheme.pfTextPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Fixed-size phases (loading/drum) are height-capped so they can't
          // overflow; the player-list phase renders inline and is scrolled by
          // the surrounding action sheet / sidebar (the single scroll region).
          if (phase == _ModalPhase.playerList)
            _body()
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: maxBodyH),
              child: _body(),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    switch (phase) {
      case _ModalPhase.loading:
        return _LoadingBody(color: color);
      case _ModalPhase.drum:
        return _DrumBody(
          result: result!,
          color: color,
          onComplete: onDrumComplete,
        );
      case _ModalPhase.playerList:
        return SubsPlayerListPicker(
          result: result!,
          color: color,
          lineup: lineup,
          onPick: onPick,
        );
    }
  }
}

// ── Modal body sections ───────────────────────────────────────────────────────

class _LoadingBody extends StatelessWidget {
  const _LoadingBody({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: CircularProgressIndicator(strokeWidth: 3, color: color),
          ),
          const SizedBox(height: 22),
          const Text(
            'Finding a club…',
            style: TextStyle(color: HETheme.pfTextSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _DrumBody extends StatelessWidget {
  const _DrumBody({
    required this.result,
    required this.color,
    required this.onComplete,
  });

  final SubSpinResult result;
  final Color color;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        // Vertical padding trimmed from the old all(24): ClubRouletteDrum
        // is actually 243px tall (72px itemExtent × 3 visible rows, plus
        // its own club-name label row) — not the ~160px a stale comment on
        // _InlineSpinnerView's maxBodyH assumed. With the old 24+24
        // vertical padding, "YOUR CLUB" (≈16px) + 16px gap + the drum's
        // 243px totalled 323px against a 320px cap: a real, reproducible
        // 3px RenderFlex overflow on every club spin. This still leaves a
        // comfortable horizontal margin, just less vertical padding.
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'YOUR CLUB',
              style: TextStyle(
                color: color.withValues(alpha: 0.75),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            ClubRouletteDrum(
              resultClub: result.clubName,
              clubPool: const [],
              itemExtent: 72,
              onComplete: onComplete,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────

class _LabelTab extends StatelessWidget {
  const _LabelTab({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Slim label pill — no background panel, just the group abbreviation
    // in the group colour. The left strip on the card already carries the
    // colour identity; this pill reinforces it without adding another border.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ── Swap action area (pending move + Swap button) ──────────────────────────────

class _SwapActionArea extends StatelessWidget {
  const _SwapActionArea({required this.subSwap});

  final SubSwapView subSwap;

  @override
  Widget build(BuildContext context) {
    // Idle — nothing selected yet.
    final src = subSwap.sourceLabel ?? 'Selected';
    final canSwap = subSwap.canSwap;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: canSwap
              ? _kPendingGold.withValues(alpha: 0.55)
              : _kSelectViolet.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canSwap)
            Row(
              children: [
                const Icon(
                  Icons.swap_horiz_rounded,
                  color: _kPendingGold,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Swap: ',
                          style: TextStyle(
                            color: HETheme.pfTextSecondary,
                            fontSize: 12,
                          ),
                        ),
                        TextSpan(
                          text: src,
                          style: const TextStyle(
                            color: HETheme.pfTextPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const TextSpan(
                          text: '  ↔  ',
                          style: TextStyle(
                            color: _kPendingGold,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TextSpan(
                          text: subSwap.targetLabel ?? '',
                          style: const TextStyle(
                            color: HETheme.pfTextPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: _kSelectViolet,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Selected: ',
                          style: TextStyle(
                            color: HETheme.pfTextSecondary,
                            fontSize: 12,
                          ),
                        ),
                        TextSpan(
                          text: src,
                          style: const TextStyle(
                            color: HETheme.pfTextPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 4),
          Text(
            canSwap
                ? 'Press Swap to apply this move.'
                : 'Tap a highlighted target to swap.',
            style: const TextStyle(color: HETheme.pfTextMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Idle hint shown once all bench subs are picked but before the player
/// taps a card to start a swap. Kept as a separate widget (rather than an
/// internal state in _SwapActionArea) so it can be toggled externally in
/// SubsPanel.build() without entering the swap-active branch.
class _SwapIdleHint extends StatelessWidget {
  const _SwapIdleHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(
            Icons.touch_app_rounded,
            color: HETheme.pfTextSecondary,
            size: 14,
          ),
          const SizedBox(width: 8),
          const Flexible(
            child: Text(
              'Tap a bench card or a player on the pitch to swap.',
              style: TextStyle(color: HETheme.pfTextSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Explicit "bench locked" moment for bench_selection.
///
/// There is no separate lock RPC — picking the 3rd sub sets `isComplete` and
/// the server advances to ability_activation when the whole room is ready.
/// This widget makes that lock feel intentional (rather than a silent wait)
/// and teases the next phase.
class _BenchLockedStatus extends StatelessWidget {
  const _BenchLockedStatus({
    required this.allPickedLocally,
    required this.opponentAllPicked,
    required this.opponentCount,
  });
  final bool allPickedLocally;
  final bool opponentAllPicked;
  final int opponentCount;

  @override
  Widget build(BuildContext context) {
    if (!allPickedLocally) {
      return Container(
        key: const ValueKey('bench-picking-hint'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: HETheme.pfSurfaceRaised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: HETheme.pfBorder),
        ),
        child: const Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              color: HETheme.pfTextMuted,
              size: 16,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Next after lock: a hidden ability phase. Rivals will not '
                'see your card until everyone locks.',
                style: TextStyle(color: HETheme.pfTextSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    final plural = opponentCount != 1;
    final ready = opponentAllPicked;
    final waitLabel = ready
        ? (plural
              ? 'Room ready — starting abilities…'
              : 'Opponent ready — starting abilities…')
        : (plural
              ? 'Waiting for opponents to lock their benches…'
              : 'Waiting for opponent to lock their bench…');

    return Container(
      key: const ValueKey('bench-locked-status'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: HETheme.pfAccentViolet.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HETheme.pfAccentViolet.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.lock_rounded, color: HETheme.pfAccentViolet, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Bench Locked',
                  style: TextStyle(
                    color: HETheme.pfAccentViolet,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Your three subs are set. Next: use your tactical card in secret.',
            style: TextStyle(color: HETheme.pfTextSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          // Presentational primary CTA — mirrors "Lineup Submitted ✓".
          // Not pressable: lock already happened via the 3rd pick.
          HEButton(label: 'Bench Locked ✓', onPressed: null),
          const SizedBox(height: 8),
          Row(
            children: [
              if (ready)
                const Icon(Icons.check_circle, color: HETheme.pfAccentViolet, size: 13)
              else
                const SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: HETheme.pfTextMuted,
                  ),
                ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  waitLabel,
                  style: TextStyle(
                    color: ready ? HETheme.pfAccentViolet : HETheme.pfTextSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Count-aware copy for the opponent status row — "opponent" reads naturally
/// in a 2-player game, but N>2 rooms have 2+ others waiting/confirming, so
/// the singular noun needs to become "opponents". Extracted as a standalone,
/// public function (rather than inlined in the widget's build method) so it
/// is directly unit-testable without needing to construct a full GameState
/// fixture just to render _OpponentStatusRow — same rationale as
/// room_provider.dart's `isCacheableId` extraction.
String opponentStatusLabel({
  required bool localConfirmed,
  required bool opponentConfirmed,
  required int opponentCount,
}) {
  final plural = opponentCount != 1;
  if (localConfirmed) {
    if (opponentConfirmed) {
      return plural
          ? 'All opponents submitted lineup ✓'
          : 'Opponent submitted lineup ✓';
    }
    return plural
        ? 'Waiting for opponents to submit…'
        : 'Waiting for opponent to submit…';
  }
  return plural
      ? 'Waiting for opponents to finish…'
      : 'Waiting for opponent to finish…';
}

class _OpponentStatusRow extends StatelessWidget {
  const _OpponentStatusRow({
    required this.allPickedLocally,
    required this.localConfirmed,
    required this.opponentConfirmed,
    required this.opponentCount,
  });
  final bool allPickedLocally;
  final bool localConfirmed;
  final bool opponentConfirmed;

  /// How many other players are in this game — 1 in a 2-player game, 2+ in
  /// an N>2 room. `opponentConfirmed` already aggregates correctly across
  /// however many there are (see subs_panel.dart's `.every(...)` check);
  /// this only decides whether the copy reads "opponent" or "opponents".
  final int opponentCount;

  @override
  Widget build(BuildContext context) {
    final showRow = allPickedLocally || localConfirmed;
    if (!showRow) return const SizedBox.shrink();

    final good = localConfirmed && opponentConfirmed;
    final label = opponentStatusLabel(
      localConfirmed: localConfirmed,
      opponentConfirmed: opponentConfirmed,
      opponentCount: opponentCount,
    );

    // Plain text row — no bordered card. The Confirm button above already
    // carries enough visual weight; this is just a status line below it.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (good)
            const Icon(Icons.check_circle, color: HETheme.pfAccentViolet, size: 13)
          else
            const SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: HETheme.pfTextMuted,
              ),
            ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: good ? HETheme.pfAccentViolet : HETheme.pfTextSecondary,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
