import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_motion.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/models/chemistry_bonus.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/services/chemistry_evaluator.dart';
import 'package:hidden_eleven/features/game/widgets/ability_marker_badges.dart';
import 'package:hidden_eleven/features/game/widgets/arena_background.dart'
    show ArenaClock;
import 'package:hidden_eleven/features/game/widgets/card_details_modal.dart';
import 'package:hidden_eleven/features/game/widgets/chemistry_constellation.dart';
import 'package:hidden_eleven/features/game/widgets/pitch_painter.dart';
import 'package:hidden_eleven/shared/widgets/jersey_back.dart';

/// Color for the pitch-tile chemistry reward badge.
/// Out-of-position cards keep their number for planning but use danger red
/// because that chemistry is not counted in scoring ([PitchSlot.cardFitsSlot]).
/// Extracted for unit tests — same rationale as `opponentStatusLabel`.
Color chemBonusBadgeColor({
  required bool outOfPosition,
  required bool captain,
}) {
  if (outOfPosition) return HETheme.pfDanger;
  if (captain) return HETheme.pfGold;
  return HETheme.pfSuccess;
}

// ── Formation slot coordinates ────────────────────────────────────────────────
// Normalised (x, y): x 0=left…1=right, y 0=attacking end…1=GK end.
// Covers every label used by the five built-in formations.
const Map<String, Offset> kSlotPositions = {
  // Goalkeeper
  'GK': Offset(0.500, 0.875),
  // Back line
  'LB': Offset(0.120, 0.730),
  'LCB': Offset(0.300, 0.730),
  'CCB': Offset(0.500, 0.730),
  'CB': Offset(0.500, 0.730),
  'RCB': Offset(0.700, 0.730),
  'RB': Offset(0.880, 0.730),
  // Wing-backs (5-3-2 – placed at the back line)
  'LWB': Offset(0.090, 0.730),
  'RWB': Offset(0.910, 0.730),
  // Defensive mid
  'LCDM': Offset(0.340, 0.575),
  'CDM': Offset(0.500, 0.575),
  'RCDM': Offset(0.660, 0.575),
  // Central & wide mid
  'LM': Offset(0.090, 0.475),
  'LCM': Offset(0.285, 0.475),
  'CM': Offset(0.500, 0.475),
  'RCM': Offset(0.715, 0.475),
  'RM': Offset(0.910, 0.475),
  // Attacking mid
  'LAM': Offset(0.225, 0.360),
  'CAM': Offset(0.500, 0.360),
  'RAM': Offset(0.775, 0.360),
  // Wide forwards
  'LW': Offset(0.125, 0.215),
  'RW': Offset(0.875, 0.215),
  // Strikers / forwards
  'LST': Offset(0.340, 0.130),
  'ST': Offset(0.500, 0.130),
  'RST': Offset(0.660, 0.130),
  'CF': Offset(0.500, 0.145),
  'SS': Offset(0.500, 0.145),
};

/// Pure geometry: the on-pitch center point for [slot]'s card given the
/// rendered pitch box size ([w] x [h]) — no clamping, no card size baked in.
///
/// This is the single source of truth for "where does this slot's card sit"
/// — [PitchView]'s own card placement ([_positionedCard]) and
/// the constellation aura painter both call this instead of each recomputing
/// the `kSlotPositions` lookup independently, so an aura and the cards it
/// surrounds can never silently drift apart.
Offset pitchSlotCenter(PitchSlot slot, double w, double h) {
  final norm =
      kSlotPositions[slot.label] ??
      kSlotPositions[slot.basePositionType] ??
      const Offset(0.5, 0.5);
  return Offset(norm.dx * w, norm.dy * h);
}

// ── Main pitch widget ─────────────────────────────────────────────────────────

class PitchView extends StatelessWidget {
  const PitchView({
    super.key,
    required this.slots,
    required this.roundSlotIndex,
    required this.isInteractiveOwner,
    required this.turnPhase,
    this.onSlotTap,
    this.subsSourceSlotIndex,
    this.subsTargetSlotIndices = const {},
    this.subsPendingTargetIndex,
    this.subsSwappedSlotIndices = const {},
    this.subsSelectionActive = false,
    this.onSubsSlotTap,
    this.highlightOutOfPosition = false,
    this.showChemistry = true,
  });

  /// All 11 slots for the viewed player's pitch.
  final List<PitchSlot> slots;

  /// The shared round-slot index, null when this is the first player's turn
  /// (they are choosing the slot).
  final int? roundSlotIndex;

  /// True only when the local player is viewing their OWN pitch and it is
  /// their turn. False for read-only (other players' pitches) and for the
  /// local player's pitch when it is not their turn.
  final bool isInteractiveOwner;

  /// Current turn phase: 'selecting_position' | 'selecting_card'
  final String turnPhase;

  /// Called when the local player taps an empty selectable slot.
  final ValueChanged<int>? onSlotTap;

  /// The pitch slot currently selected as the swap SOURCE (solid violet).
  final int? subsSourceSlotIndex;

  /// Pitch slots eligible to be chosen as the swap TARGET (violet glow).
  final Set<int> subsTargetSlotIndices;

  /// The pitch slot chosen as the pending TARGET, awaiting [Swap] (gold).
  final int? subsPendingTargetIndex;

  /// Slots already holding a swapped-in sub (emerald/success) — shown when idle.
  final Set<int> subsSwappedSlotIndices;

  /// True while a source is selected — non-target cards are dimmed/inactive.
  final bool subsSelectionActive;

  /// Called when the player taps a filled slot during the subs phase.
  final ValueChanged<PitchSlot>? onSubsSlotTap;

  /// When true (e.g. on the result screen), filled cards that don't fit their
  /// slot are flagged red even though selection is inactive — they scored 0.
  final bool highlightOutOfPosition;

  /// Whether chemistry (badges, progress bar, details-modal breakdown) may be
  /// shown for this pitch. False for every pitch except the local player's
  /// own — chemistry challenges are private, per-player competitive info.
  /// Defaults to true so existing callers (e.g. the post-game result screen,
  /// where full reveal is intentional) are unaffected.
  final bool showChemistry;

  /// A slot is selectable only when: interactive owner, phase=selecting_position,
  /// round slot not yet chosen, slot is empty.
  bool _isSelectable(PitchSlot slot) =>
      isInteractiveOwner &&
      turnPhase == 'selecting_position' &&
      roundSlotIndex == null &&
      !slot.isFilled;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.625, // portrait pitch — 5:8 w:h
      child: LayoutBuilder(
        builder: (ctx, box) {
          final w = box.maxWidth;
          final h = box.maxHeight;
          final cardW = (w * 0.155).clamp(40.0, 70.0);
          final cardH = cardW * 1.18;

          // The pitch's share of the arena's ambient life. Read from the
          // shared ArenaClock rather than a controller of this widget's own,
          // so the whole game screen still runs exactly one ambient loop.
          // Null outside an arena (e.g. the result screen) and under reduced
          // motion — the painter then draws its static resting state.
          final clock = ArenaClock.maybeOf(ctx);

          final markers = showChemistry
              ? constellationMarkers(slots)
              : const <int, ChemistryGroupType>{};

          return ClipRRect(
            borderRadius: BorderRadius.circular(HEShape.rLg),
            child: Stack(
              children: [
                // Pitch background
                Positioned.fill(
                  child: RepaintBoundary(
                    child: clock == null
                        ? const CustomPaint(painter: PitchPainter())
                        : AnimatedBuilder(
                            animation: clock,
                            builder: (_, _) => CustomPaint(
                              painter: PitchPainter(lightT: clock.value),
                            ),
                          ),
                  ),
                ),

                // No chemistry geometry is drawn on the pitch. The group aura
                // + corner label that used to sit here were removed: an
                // overlay shape asks the player to decode geometry to learn
                // something that is really a list of facts, it conflicted
                // visually with the cards (especially at phone widths), and it
                // could only express group *membership*, never chemistry
                // quality. `TeamChemistrySummary` states the same information
                // as a one-glance readout instead, and the per-card C/L/N
                // markers below still show which players are linked. The
                // grouping logic itself (`computeChemistryGroups` /
                // `constellationMarkers`) is unchanged and still feeds both.

                // Position cards
                for (final slot in slots)
                  _positionedCard(
                    slot,
                    w,
                    h,
                    cardW,
                    cardH,
                    markers[slot.index],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _positionedCard(
    PitchSlot slot,
    double pw,
    double ph,
    double cw,
    double ch,
    ChemistryGroupType? marker,
  ) {
    final center = pitchSlotCenter(slot, pw, ph);
    final cx = center.dx;
    final cy = center.dy;

    // Clamp so card never bleeds outside the pitch.
    final left = (cx - cw / 2).clamp(2.0, pw - cw - 2.0);
    final top = (cy - ch / 2).clamp(2.0, ph - ch - 2.0);

    final isRound = roundSlotIndex == slot.index;
    final selectable = _isSelectable(slot);

    // Subs-phase selection states for this slot.
    final isSource = subsSourceSlotIndex == slot.index;
    final isPending = subsPendingTargetIndex == slot.index;
    final isTarget = subsTargetSlotIndices.contains(slot.index) && !isPending;
    final isSubsSwapped = subsSwappedSlotIndices.contains(slot.index);
    final subsActive = onSubsSlotTap != null && slot.isFilled;
    // When a source is selected, source/targets/pending get the highlight.
    final involved = isSource || isTarget || isPending;
    // A starter whose card no longer fits its slot (after a free rearrange, or
    // left out of position when the subs timer expired → scored 0).
    final isInvalid =
        (subsActive || highlightOutOfPosition) &&
        slot.isFilled &&
        !slot.cardFitsSlot;
    // Dim only non-involved, non-glowing cards as a hint — but keep them
    // tappable so any starter can be chosen for a pitch↔pitch swap.
    final dimmed = subsSelectionActive && subsActive && !involved && !isInvalid;

    VoidCallback? tapHandler;
    if (selectable) {
      tapHandler = () => onSlotTap?.call(slot.index);
    } else if (subsActive) {
      // Every filled starter is tappable during subs: as a source, or as a
      // pitch↔pitch target once a source is selected.
      tapHandler = () => onSubsSlotTap?.call(slot);
    }

    Widget card = _PositionCard(
      slot: slot,
      isRoundSlot: isRound,
      isSelectable: selectable,
      isSubsSource: isSource,
      isSubsTarget: isTarget,
      isSubsPending: isPending,
      isSubsSwapped: isSubsSwapped && !involved,
      isSubsInvalid: isInvalid && !involved,
      // During the subs phase, suppress the card-details modal fallback so
      // inert (dimmed) cards don't open a dialog on tap.
      subsMode: onSubsSlotTap != null,
      // Show the card's own allowed positions during subs AND on the result
      // screen, so out-of-position (red) cards are explained at a glance.
      showAllowedPositions: onSubsSlotTap != null || highlightOutOfPosition,
      allSlots: slots,
      showChemistry: showChemistry,
      onTap: tapHandler,
    );
    if (dimmed) {
      card = Opacity(opacity: 0.38, child: card);
    }

    // The constellation marker sits OUTSIDE the card's own layout, pinned to
    // its top-left corner, so it can never overlap the rating, name, position
    // or the existing `+N` chemistry reward badge (which lives top-right).
    if (marker != null && slot.isFilled) {
      card = Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          Positioned(
            top: -4,
            left: -4,
            child: IgnorePointer(child: ConstellationMarker(type: marker)),
          ),
        ],
      );
    }

    return Positioned(left: left, top: top, width: cw, height: ch, child: card);
  }
}

// ── Position card ─────────────────────────────────────────────────────────────

class _PositionCard extends StatelessWidget {
  const _PositionCard({
    required this.slot,
    required this.isRoundSlot,
    required this.isSelectable,
    required this.isSubsSource,
    required this.isSubsTarget,
    required this.isSubsPending,
    required this.isSubsSwapped,
    required this.isSubsInvalid,
    required this.subsMode,
    required this.showAllowedPositions,
    required this.allSlots,
    required this.showChemistry,
    this.onTap,
  });

  final PitchSlot slot;
  final bool isRoundSlot;
  final bool isSelectable;
  final bool isSubsSource;
  final bool isSubsTarget;
  final bool isSubsPending;
  final bool isSubsSwapped;
  final bool isSubsInvalid;
  final bool subsMode;
  final bool showAllowedPositions;
  final List<PitchSlot> allSlots;
  final bool showChemistry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Keyed by the card actually occupying this slot (or 'empty'), so
    // AnimatedSwitcher plays the landing pop exactly when a slot goes from
    // empty to filled (or the card in it changes via a subs swap) — not on
    // every rebuild the slot goes through while nothing about its card has
    // changed (selection highlight, dimming, etc).
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 340),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: KeyedSubtree(
        key: ValueKey(slot.cardId ?? 'empty-${slot.index}'),
        child: _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (slot.isFilled) {
      void openDetails() {
        final lineup = allSlots
            .where((s) => s.isFilled)
            .map(LineupCard.fromSlot)
            .toList();
        // Show the card's OWN supported positions (primary + alternates), not
        // the slot label — they differ when a starter is out of position.
        final nat = slot.effectiveNaturalPositions;
        final primary = nat.isNotEmpty ? nat.first : slot.label;
        showCardDetailsModal(
          context,
          playerName: slot.cardPlayerName ?? '',
          rating: slot.cardRating ?? 0,
          position: primary,
          imageSeed: slot.cardId ?? slot.cardPlayerName,
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
          pace: slot.cardPace,
          shooting: slot.cardShooting,
          passing: slot.cardPassing,
          dribbling: slot.cardDribbling,
          defending: slot.cardDefending,
          physical: slot.cardPhysical,
          chemistryBonuses: showChemistry
              ? slot.cardChemistryBonuses
              : const [],
          lineup: lineup,
        );
      }

      // Outside the subs phase a filled card opens its details modal on tap.
      // During subs, taps drive selection (onTap); a long-press still opens
      // details so the starting XI can be inspected mid-swap.
      final VoidCallback? filledTap = onTap ?? (subsMode ? null : openDetails);
      final card = GestureDetector(
        onTap: filledTap,
        onLongPress: openDetails,
        child: _FilledCard(
          slot: slot,
          isRoundSlot: isRoundSlot,
          isSubsSource: isSubsSource,
          isSubsTarget: isSubsTarget,
          isSubsPending: isSubsPending,
          isSubsSwapped: isSubsSwapped,
          isSubsInvalid: isSubsInvalid,
          allSlots: allSlots,
          subsMode: showAllowedPositions,
          showChemistry: showChemistry,
        ),
      );
      // During subs a plain tap is reserved for swap-selection, so expose an
      // explicit ⓘ button (mirrors the bench cards) that opens the card's
      // challenge breakdown without triggering a swap.
      if (!subsMode) return card;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          Positioned(
            top: -6,
            left: -6,
            child: GestureDetector(
              onTap: openDetails,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: HETheme.pfSurfaceDeep,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: HETheme.pfAccentViolet.withValues(alpha: 0.7),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.info_outline,
                  size: 14,
                  color: HETheme.pfAccentViolet,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return _EmptyCard(
      slot: slot,
      isRoundSlot: isRoundSlot,
      isSelectable: isSelectable,
      onTap: onTap,
    );
  }
}

// ── Filled card ───────────────────────────────────────────────────────────────

class _FilledCard extends StatelessWidget {
  const _FilledCard({
    required this.slot,
    required this.isRoundSlot,
    required this.isSubsSource,
    required this.isSubsTarget,
    required this.isSubsPending,
    required this.isSubsSwapped,
    required this.isSubsInvalid,
    required this.allSlots,
    required this.showChemistry,
    this.subsMode = false,
  });

  final PitchSlot slot;
  final bool isRoundSlot;
  final bool isSubsSource;
  final bool isSubsTarget;
  final bool isSubsPending;
  final bool isSubsSwapped;
  final bool isSubsInvalid;
  final List<PitchSlot> allSlots;

  /// Whether chemistry badges/progress may be computed and shown for this
  /// card — false for every pitch except the local player's own.
  final bool showChemistry;

  /// During the subs phase, show the card's own allowed positions under the
  /// slot label so the player can plan swaps without opening details.
  final bool subsMode;

  @override
  Widget build(BuildContext context) {
    final tier = CardTier.forCard(slot.cardRating ?? 0, slot.cardStyle);

    // Priority: source > pending target > eligible target > existing swap >
    // round slot > default
    final Color borderColor;
    final double borderW;
    final List<BoxShadow> extraGlow;

    if (isSubsSource) {
      // Outgoing player — a selection, not a success; violet per the shared
      // swap-state vocabulary (mirrors subs_panel.dart's ring treatment).
      borderColor = HETheme.pfAccentViolet;
      borderW = 2.5;
      extraGlow = [
        BoxShadow(
          color: HETheme.pfAccentViolet.withValues(alpha: 0.60),
          blurRadius: 12,
          spreadRadius: 2,
        ),
      ];
    } else if (isSubsPending) {
      // Chosen target awaiting the Swap button — gold, "highlighted, about
      // to commit" (matches subs_panel.dart's pending treatment).
      borderColor = HETheme.pfGold;
      borderW = 2.5;
      extraGlow = [
        BoxShadow(
          color: HETheme.pfGold.withValues(alpha: 0.60),
          blurRadius: 12,
          spreadRadius: 2,
        ),
      ];
    } else if (isSubsTarget) {
      // Valid, unselected target — lighter violet-glow so it reads as
      // "selectable" without competing with the solid source ring.
      borderColor = HETheme.pfAccentVioletGlow;
      borderW = 2.0;
      extraGlow = [
        BoxShadow(
          color: HETheme.pfAccentVioletGlow.withValues(alpha: 0.45),
          blurRadius: 10,
          spreadRadius: 1,
        ),
      ];
    } else if (isSubsInvalid) {
      borderColor = HETheme.pfDanger;
      borderW = 2.5;
      extraGlow = [
        BoxShadow(
          color: HETheme.pfDanger.withValues(alpha: 0.55),
          blurRadius: 12,
          spreadRadius: 2,
        ),
      ];
    } else if (isSubsSwapped) {
      // A completed, still-undoable swap now starting on the pitch — an
      // actual completed/valid state, so emerald/success per the vocabulary
      // (previously amber, which the vocabulary reserves for "pending").
      borderColor = HETheme.pfSuccess;
      borderW = 2.0;
      extraGlow = [
        BoxShadow(
          color: HETheme.pfSuccess.withValues(alpha: 0.45),
          blurRadius: 10,
          spreadRadius: 1,
        ),
      ];
    } else if (isRoundSlot) {
      borderColor = HETheme.pfAccentViolet;
      borderW = 1.5;
      extraGlow = [
        BoxShadow(
          color: HETheme.pfAccentViolet.withValues(alpha: 0.35),
          blurRadius: 10,
          spreadRadius: 1,
        ),
      ];
    } else {
      borderColor = tier.borderColor;
      borderW = 1.0;
      extraGlow = [];
    }

    // Evaluate this card's 3 tiered challenges against the full lineup. Red-
    // carded cards are excluded from the lineup so they neither earn chemistry
    // nor prop up teammates (matching the scoring engine). Chemistry is
    // private, per-player info — showChemistry is false for every pitch
    // except the local player's own, so opponents' cards never compute or
    // display a badge/progress bar here.
    final bonuses = showChemistry
        ? slot.cardChemistryBonuses
        : const <ChemistryBonus>[];
    int earnedReward = 0; // sum of satisfied tier rewards (0..12)
    double bestProgress = 0.0;
    if (bonuses.isNotEmpty && !slot.isRedCarded) {
      final lineup = allSlots
          .where((s) => s.isFilled && !s.isRedCarded)
          .map(LineupCard.fromSlot)
          .toList();
      earnedReward = ChemistryEvaluator.earnedReward(
        bonuses,
        lineup,
        ownerClub: slot.cardClub,
      );
      // Show progress toward the next unsatisfied tier when none earned yet.
      if (earnedReward == 0) {
        for (var i = 0; i < bonuses.length; i++) {
          final prog = ChemistryEvaluator.progressOf(bonuses[i], lineup);
          if (prog.required > 0 && prog.current > 0) {
            final f = prog.current / prog.required;
            if (f > bestProgress) bestProgress = f;
          }
        }
      }
    }
    // Captain doubles the displayed chemistry; red-carded shows 0.
    final displayReward = slot.isCaptain ? earnedReward * 2 : earnedReward;
    final bonusEarned = earnedReward > 0;
    final showSubsTopLeft =
        isSubsSource ||
        isSubsPending ||
        isSubsTarget ||
        isSubsSwapped ||
        isSubsInvalid;

    return LayoutBuilder(
      builder: (ctx, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        final nameFontSize = (w * 0.145).clamp(7.5, 11.0);
        final labelFontSize = (w * 0.110).clamp(6.5, 9.0);
        final ratingFontSize = (w * 0.118).clamp(7.0, 9.5);
        final imageH = h * 0.52;
        // On small mobile pitch tiles, showing the position label under the
        // name (e.g. "CB") is redundant clutter — the image + rating +
        // name already identify an occupied slot, and FittedBox shrinking
        // both lines together just makes everything harder to read. Purely
        // width-based (not a platform check, per the app's own layout
        // convention) so desktop's larger tiles are unaffected. Always kept
        // during subsMode, where the label plus the card's own allowed
        // positions below it are functionally needed to plan a swap, not
        // decorative.
        final showPositionLabel = subsMode || w >= 60;

        return Stack(
          children: [
            // ── Card body ───────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor, width: borderW),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                  ...extraGlow,
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Image zone
                    SizedBox(
                      height: imageH,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _PitchPlayerImage(slot: slot),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: imageH * 0.50,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Color(0xCC0D1322),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (slot.cardRating != null)
                            Positioned(
                              bottom: 2,
                              left: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  '${slot.cardRating}',
                                  style: TextStyle(
                                    color: tier.accentColor,
                                    fontSize: ratingFontSize,
                                    fontWeight: FontWeight.w900,
                                    height: 1.0,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Name + position band. The whole block is wrapped in a
                    // FittedBox(scaleDown) so it can NEVER overflow this
                    // Expanded's tight height, however small a pitch tile gets
                    // (very small mobile tiles, or the 3-line subs-mode variant
                    // below) — it shrinks together instead of clipping/
                    // overflowing by a few pixels. mainAxisSize.min is required
                    // for a Column to size itself inside FittedBox's
                    // unconstrained layout pass.
                    Expanded(
                      child: Container(
                        color: HETheme.pfSurfaceDeep,
                        alignment: Alignment.center,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: w * 0.06,
                                ),
                                child: Text(
                                  slot.cardPlayerName ?? '',
                                  style: TextStyle(
                                    color: HETheme.pfTextPrimary,
                                    fontSize: nameFontSize,
                                    fontWeight: FontWeight.w700,
                                    height: 1.1,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (showPositionLabel) ...[
                                SizedBox(height: h * 0.020),
                                Text(
                                  slot.label,
                                  style: TextStyle(
                                    color: isSubsSource
                                        ? HETheme.pfAccentViolet
                                        : isSubsPending
                                        ? HETheme.pfGold.withValues(alpha: 0.90)
                                        : isSubsSwapped
                                        ? HETheme.pfSuccess.withValues(
                                            alpha: 0.90,
                                          )
                                        : (isSubsTarget || isRoundSlot)
                                        ? HETheme.pfAccentVioletGlow
                                        : tier.accentColor.withValues(
                                            alpha: 0.75,
                                          ),
                                    fontSize: labelFontSize,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                              // During subs: the card's own allowed positions, so
                              // the player can plan swaps at a glance. Red when the
                              // card doesn't fit its current slot.
                              if (subsMode &&
                                  slot
                                      .effectiveNaturalPositions
                                      .isNotEmpty) ...[
                                SizedBox(height: h * 0.012),
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: w * 0.04,
                                  ),
                                  child: Text(
                                    slot.effectiveNaturalPositions.join(' · '),
                                    style: TextStyle(
                                      color: slot.cardFitsSlot
                                          ? HETheme.pfTextSecondary
                                          : HETheme.pfDanger,
                                      fontSize: (w * 0.092).clamp(5.5, 8.0),
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.2,
                                      height: 1.0,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Sub state icon (top-left, during subs phase) ────────────
            if (isSubsSource || isSubsPending || isSubsTarget || isSubsSwapped)
              Positioned(
                top: 3,
                left: 3,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: isSubsSource
                        ? HETheme.pfAccentViolet.withValues(alpha: 0.90)
                        : isSubsPending
                        ? HETheme.pfGold.withValues(alpha: 0.85)
                        : isSubsSwapped
                        ? HETheme.pfSuccess.withValues(alpha: 0.85)
                        : HETheme.pfAccentVioletGlow.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    isSubsSource
                        ? Icons.check_rounded
                        : isSubsSwapped
                        ? Icons.undo_rounded
                        : Icons.swap_horiz_rounded,
                    size: 11,
                    color: Colors.black.withValues(alpha: 0.85),
                  ),
                ),
              )
            // Out-of-position warning (top-left) when not in an active selection.
            else if (isSubsInvalid)
              Positioned(
                top: 3,
                left: 3,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: HETheme.pfDanger.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.priority_high_rounded,
                    size: 11,
                    color: Colors.white,
                  ),
                ),
              ),

            // ── Reward badge (top-right): shows earned chemistry total ───
            if (bonuses.isNotEmpty)
              Positioned(
                top: 3,
                right: 3,
                child: _ChemBonusBadge(
                  earnedReward: displayReward,
                  captain: slot.isCaptain,
                  // Out-of-position cards do not count chemistry in scoring —
                  // keep the number visible for planning, but paint it danger
                  // red so it never reads as a normal green earn.
                  outOfPosition: !slot.cardFitsSlot,
                ),
              ),

            // ── Red-card overlay: red wash + card icon (chemistry killed) ──
            if (slot.isRedCarded) ...[
              const Positioned.fill(child: RedCardWashOverlay()),
              if (!showSubsTopLeft)
                const Positioned(top: 3, left: 3, child: RedCardIconBadge()),
            ],

            // ── Sub-swap badge (bottom-left swap icon) ───────────────────
            if (slot.isSubSwapped)
              const Positioned(bottom: 3, left: 3, child: SubSwapBadge()),

            // ── Captain armband (bottom-right gold "C") ──────────────────
            if (slot.isCaptain)
              const Positioned(
                bottom: 3,
                right: 3,
                child: CaptainArmbandBadge(),
              ),

            // ── Amber progress bar (bottom, State 2: partial progress) ───
            if (bonuses.isNotEmpty && !bonusEarned && bestProgress > 0)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                  child: _CardProgressBar(progress: bestProgress),
                ),
              ),

            // ── Coach highlight (purple outer ring + glow) ────────────────
            // Card-level treatment, not another badge — see
            // CoachedCardHighlight's doc comment for why. Painted last so it
            // sits on top of everything else without covering any content
            // (IgnorePointer + a border/shadow-only decoration).
            if (slot.isCoached)
              const Positioned.fill(child: CoachedCardHighlight()),
          ],
        );
      },
    );
  }
}

// ── Chemistry bonus badge ─────────────────────────────────────────────────────

class _ChemBonusBadge extends StatelessWidget {
  const _ChemBonusBadge({
    required this.earnedReward,
    this.captain = false,
    this.outOfPosition = false,
  });

  /// Sum of satisfied tier rewards on this card (0..12), doubled if captained.
  final int earnedReward;

  /// When true the card is captained — badge turns gold to flag doubled chem
  /// (unless [outOfPosition], which overrides to danger red).
  final bool captain;

  /// True when the card does not fit its current slot — chemistry is not
  /// counted normally (see PitchSlot.cardFitsSlot / scoring).
  final bool outOfPosition;

  @override
  Widget build(BuildContext context) {
    final earned = earnedReward > 0;
    final color = chemBonusBadgeColor(
      outOfPosition: outOfPosition,
      captain: captain,
    );
    final onColor = (!outOfPosition && captain) ? Colors.black : Colors.white;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: Tween(begin: 0.5, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
        ),
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: earned
          ? Container(
              key: ValueKey('badge-$earnedReward-$captain-$outOfPosition'),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xAA000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Text(
                '+$earnedReward',
                style: TextStyle(
                  color: onColor,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
            )
          : const SizedBox.shrink(key: ValueKey('no-badge')),
    );
  }
}

// ── Amber progress bar (State 2: at least one bonus partially in progress) ───

class _CardProgressBar extends StatelessWidget {
  const _CardProgressBar({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 4,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        builder: (context, value, _) => Stack(
          children: [
            Container(color: Colors.white.withValues(alpha: 0.08)),
            FractionallySizedBox(
              widthFactor: value,
              alignment: Alignment.centerLeft,
              child: Container(
                decoration: const BoxDecoration(
                  color: HETheme.pfGold,
                  borderRadius: BorderRadius.only(
                    bottomRight: Radius.circular(4),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pitch card player image ───────────────────────────────────────────────────

class _PitchPlayerImage extends StatelessWidget {
  const _PitchPlayerImage({required this.slot});

  final PitchSlot slot;

  @override
  Widget build(BuildContext context) {
    return JerseyBack(
      playerName: slot.cardPlayerName ?? '?',
      club: slot.cardClub ?? '',
      primaryColorHex: slot.cardPrimaryColor,
      secondaryColorHex: slot.cardSecondaryColor,
      tertiaryColorHex: slot.cardTertiaryColor,
      kitPattern: kitPatternFromName(slot.cardKitPattern),
      numberSeed: slot.cardId,
      kitNumber: slot.cardKitNumber,
    );
  }
}

// ── Empty card ────────────────────────────────────────────────────────────────

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.slot,
    required this.isRoundSlot,
    required this.isSelectable,
    this.onTap,
  });

  final PitchSlot slot;
  final bool isRoundSlot;
  final bool isSelectable;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // An empty slot is a *socket* under Night Tactics — a recess in the
    // pitch waiting to be filled — rather than a bright cyan tile competing
    // with the filled cards around it. Three states, each meaning-locked:
    //
    //   selectable  violet, breathing  "you can tap this right now"
    //   round slot  magenta, pulsing   the one hot thing on screen
    //   idle        matte, dashed      a recess, deliberately quiet
    final Color bg;
    final Color border;
    final Color label;
    final double borderW;
    final List<BoxShadow> shadows;

    if (isSelectable) {
      bg = HETheme.pfAccentViolet.withValues(alpha: 0.16);
      border = HETheme.pfAccentViolet;
      label = HETheme.pfLavenderText;
      borderW = 1.5;
      shadows = [
        BoxShadow(
          color: HETheme.pfAccentViolet.withValues(alpha: 0.45),
          blurRadius: 14,
          spreadRadius: 1,
        ),
      ];
    } else if (isRoundSlot) {
      bg = HETheme.pfAccentMagenta.withValues(alpha: 0.14);
      border = HETheme.pfAccentMagenta;
      label = HETheme.pfTextPrimary;
      borderW = 2.0;
      shadows = [
        BoxShadow(
          color: HETheme.pfAccentMagenta.withValues(alpha: 0.42),
          blurRadius: 18,
          spreadRadius: 1,
        ),
      ];
    } else {
      bg = HETheme.pfSurfaceRaised.withValues(alpha: 0.55);
      border = HETheme.pfSecondaryViolet.withValues(alpha: 0.45);
      label = HETheme.pfTextMuted;
      borderW = 1.0;
      shadows = [
        // Inner-shadow substitute: a tight dark drop under the socket reads
        // as a recess rather than a raised tile.
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.28),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: HEMotion.focus,
        curve: HEMotion.easeOut,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(HEShape.rMd),
          border: Border.all(color: border, width: borderW),
          boxShadow: shadows,
        ),
        // Placeholder label scales with the tile instead of a flat 8.5px —
        // that read as cramped/hard to read on the smallest mobile tiles
        // and needlessly small on larger desktop ones. FittedBox is a
        // safety net for the narrowest formations' tightest slots, not the
        // primary sizing mechanism.
        // The position label sits in a pill badge rather than as bare text
        // on the tile — part of the shape system's rule that passive
        // information reads as a chip. Font size still scales with the tile
        // (a flat size read as cramped on the smallest mobile slots and
        // needlessly small on desktop); FittedBox remains the safety net for
        // the narrowest formations, not the primary sizing mechanism.
        child: LayoutBuilder(
          builder: (ctx, box) {
            final labelFontSize = (box.maxWidth * 0.20).clamp(8.0, 13.0);
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: HETheme.pfBgVoid.withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(HEShape.rPill),
                      border: Border.all(color: border.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      slot.label,
                      style: TextStyle(
                        color: label,
                        fontSize: labelFontSize,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
