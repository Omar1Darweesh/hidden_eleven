import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';

import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/widgets/dossier_shuffle.dart';
import 'package:hidden_eleven/features/game/widgets/panel_header.dart';
import 'package:hidden_eleven/features/game/widgets/player_card.dart';
import 'package:hidden_eleven/features/game/widgets/sealed_dossier_card.dart';

// HiddenSlotInfo is defined in game_state.dart (imported above).

// ── Panel ─────────────────────────────────────────────────────────────────────

/// Displays face-down card slots for the hidden-pick phase.
///
/// Slot layout is a plain [Wrap] — no reorder capability, no drag handles.
///
/// [isActivePicker] — true when it is THIS player's turn to pick.
/// [totalSlots]     — total number of slots in the ordered hidden deck.
/// [availableSlots] — 0-based indices still available to pick.
/// [slotMeta]       — per-slot metadata from the server. Taken slots use this
///                    to show picker name and, when present, the card face.
/// [waitingForName] — display name of the player currently picking (when not active).
/// [onPick]         — called with the 0-based slot index when the active picker taps.
/// [onCardTap]      — called with the card when a taken (revealed) slot is tapped.
/// [previewCards]   — the remaining deck, server-sorted by cardId (NOT real
///                    slot order — see [HiddenDraftIntro]'s doc comment).
///                    Drives the one-time "magician" intro animation for the
///                    active picker only; ignored otherwise.
class HiddenPickPanel extends StatefulWidget {
  const HiddenPickPanel({
    super.key,
    required this.isActivePicker,
    required this.totalSlots,
    required this.availableSlots,
    this.slotMeta = const [],
    this.previewCards = const [],
    this.waitingForName,
    this.onPick,
    this.onCardTap,
  });

  final bool isActivePicker;
  final int totalSlots;
  final List<int> availableSlots;
  final List<HiddenSlotInfo> slotMeta;
  final List<CandidateCard> previewCards;
  final String? waitingForName;
  final ValueChanged<int>? onPick;
  final ValueChanged<CandidateCard>? onCardTap;

  @override
  State<HiddenPickPanel> createState() => _HiddenPickPanelState();
}

class _HiddenPickPanelState extends State<HiddenPickPanel> {
  /// True once the reveal → conceal → shuffle intro has finished (or was
  /// skipped/never applicable) and the real face-down slot grid should show.
  ///
  /// Deliberately plain [State], not a Riverpod provider — the caller
  /// (game_screen.dart) gives this widget a `Key` derived from the turn id,
  /// so Flutter creates fresh `State` (and thus replays the intro) exactly
  /// once per distinct hidden-pick turn. Any OTHER rebuild while the SAME
  /// turn is still current — an unrelated game_state update, a reconnect
  /// that resolves back onto the same still-active turn — reuses this same
  /// State object and `_introDone` stays whatever it already was, so the
  /// intro never replays mid-choice. See [HiddenDraftIntro] for the
  /// animation itself and its own reduced-motion / interruption handling.
  late bool _introDone = !_shouldShowIntro;

  bool get _shouldShowIntro =>
      widget.isActivePicker && widget.previewCards.isNotEmpty;

  bool _isAvailable(int index) => widget.availableSlots.contains(index);

  /// The slot the local player just tapped, while `pick_hidden_slot` is still
  /// in flight. Purely presentational — the pick itself is sent immediately
  /// on tap exactly as before; this only drives the lift/dim/seal-close
  /// feedback so the choice reads as committed rather than silent.
  ///
  /// Cleared whenever the available slots change, i.e. when the server's
  /// authoritative `game_state` lands and this grid re-renders for real.
  int? _pickedIndex;

  void _onIntroComplete() {
    if (!mounted || _introDone) return;
    setState(() => _introDone = true);
  }

  void _onPick(int index) {
    if (_pickedIndex != null) return; // one pick per turn
    setState(() => _pickedIndex = index);
    widget.onPick?.call(index);
  }

  @override
  void didUpdateWidget(HiddenPickPanel old) {
    super.didUpdateWidget(old);
    // The authoritative update arrived — drop the optimistic state so the
    // grid reflects the server, never a stale local guess.
    if (old.availableSlots.length != widget.availableSlots.length ||
        old.isActivePicker != widget.isActivePicker) {
      _pickedIndex = null;
    }
  }

  // No outer bordered card here — this panel renders inside GameActionSheet,
  // which already supplies the one frame around whatever the current phase
  // needs. A second border/shadow around the content would just be a card
  // nested inside a card.
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader(
          icon: widget.isActivePicker
              ? Icons.help_outline_rounded
              : Icons.hourglass_top_rounded,
          eyebrow: widget.isActivePicker ? 'YOUR PICK' : 'HIDDEN DRAFT',
          title: widget.isActivePicker
              ? "Choose a card — you can't see what's inside!"
              : 'Waiting for ${widget.waitingForName ?? '—'} to pick…',
          emphasized: widget.isActivePicker,
        ),
        const SizedBox(height: 12),
        // Crossfades between the intro sequence and the real grid so the
        // hand-off reads as a deliberate "settle," not an abrupt cut.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: !_introDone
              ? HiddenDraftIntro(
                  key: const ValueKey('intro'),
                  previewCards: widget.previewCards,
                  onComplete: _onIntroComplete,
                )
              : KeyedSubtree(
                  key: const ValueKey('grid'),
                  // Uses Wrap — no ReorderableListView, no drag handles.
                  child: widget.totalSlots == 0
                      ? const _EmptyState()
                      : _SlotGrid(
                          totalSlots: widget.totalSlots,
                          availableSlots: widget.availableSlots,
                          slotMeta: widget.slotMeta,
                          isActivePicker: widget.isActivePicker,
                          isAvailable: _isAvailable,
                          pickedIndex: _pickedIndex,
                          onPick: _onPick,
                          onCardTap: widget.onCardTap,
                        ),
                ),
        ),
      ],
    );
  }
}

// ── Magician intro (reveal → conceal → shuffle) ─────────────────────────────────

/// The suspense sequence shown once to the active hidden-pick player before
/// the real face-down slot grid appears: the remaining cards are shown face
/// up, flipped face down, given a short decorative shuffle, then the whole
/// thing hands off to [HiddenPickPanel]'s real `_SlotGrid` via [onComplete].
///
/// **This animation is illusion only — it can never touch gameplay truth.**
/// [previewCards] is the server's `cardId`-sorted list (see
/// `HiddenPickPromptReceived`'s doc comment), which is DELIBERATELY not the
/// real slot order — the real order (`orderedHiddenDeck` server-side) is
/// never sent to the client at all, before or after this animation. The
/// on-screen "shuffle" only ever reassigns which of THIS WIDGET's own
/// temporary display positions each preview card visually sits in; those
/// positions have no relationship whatsoever to the real slot indices the
/// eventual `_SlotGrid` renders — this widget never even receives slot
/// indices. When it finishes, `HiddenPickPanel` swaps it out entirely for
/// the unchanged, pre-existing `_SlotGrid`, whose taps go through the exact
/// same `onPick(slotIndex)` → `pick_hidden_slot` path this game always used.
/// There is no "landing" step where a specific preview card is mapped onto a
/// specific final slot — the crossfade in `_HiddenPickPanelState.build`
/// deliberately has no visual continuity between the two, so it can't even
/// accidentally imply one.
///
/// Respects the platform's reduced-motion setting
/// (`MediaQuery.disableAnimations`) — when set, the whole sequence is
/// skipped and [onComplete] fires immediately. Safe to interrupt at any
/// point: all timers/controllers are cancelled in [dispose], and
/// [onComplete] is guarded against firing twice.
class HiddenDraftIntro extends StatefulWidget {
  const HiddenDraftIntro({
    super.key,
    required this.previewCards,
    required this.onComplete,
  });

  final List<CandidateCard> previewCards;
  final VoidCallback onComplete;

  @override
  State<HiddenDraftIntro> createState() => _HiddenDraftIntroState();
}

class _HiddenDraftIntroState extends State<HiddenDraftIntro>
    with SingleTickerProviderStateMixin {
  /// The ONE controller driving the whole sequence — entrance, preview hold,
  /// flip, three shuffle moves and settle. Replaces the nine raw `Timer`s
  /// this used to run on: one object to create, one to dispose, and a
  /// timeline that can actually be scrubbed and tested. See
  /// [DossierShuffleTimeline] for the stage boundaries and the
  /// content-blindness contract every motion parameter obeys.
  ///
  /// Null when motion is reduced — no controller is constructed at all.
  AnimationController? _ctrl;

  /// Base display order: `_base[i]` is the index into `widget.previewCards`
  /// shown at display position `i` before any shuffle move. Only ever
  /// permuted among ITSELF by [DossierShuffleTimeline.orderAt] — purely
  /// cosmetic, never derived from or fed back into any real slot data.
  late List<int> _base;

  bool _started = false;
  bool _completedOnce = false;

  @override
  void initState() {
    super.initState();
    _base = List.generate(widget.previewCards.length, (i) => i);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Guarded to run exactly once — didChangeDependencies can fire again
    // later (e.g. a theme/locale change) and must not restart the sequence.
    if (_started) return;
    _started = true;

    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reducedMotion || widget.previewCards.isEmpty) {
      // Never block the player behind a decorative sequence: skip straight
      // to the real slots. Deferred a frame so onComplete (which triggers a
      // parent setState) never fires mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
      return;
    }

    _ctrl =
        AnimationController(vsync: this, duration: DossierShuffleTimeline.total)
          ..addStatusListener((s) {
            if (s == AnimationStatus.completed) _finish();
          });
    _ctrl!.forward();
  }

  /// Handles [HiddenDraftIntro.previewCards] changing while the sequence is
  /// in flight.
  ///
  /// This previously went unhandled: `_order` is a permutation of INDICES
  /// into `previewCards`, so a shorter list arriving mid-sequence left stale
  /// indices that would throw on the next build (RangeError). A server
  /// correction or a reconnect resolving onto slightly different remaining
  /// cards is enough to trigger it.
  ///
  /// The fix reconciles the permutation WITHOUT restarting the controller —
  /// restarting would replay the whole intro mid-choice, which is exactly
  /// what the parent's stable `ValueKey('intro')` and `_introDone` exist to
  /// prevent. It also cannot leak identity: the rebuilt order is the plain
  /// identity permutation, derived from the new length alone.
  @override
  void didUpdateWidget(HiddenDraftIntro old) {
    super.didUpdateWidget(old);
    final n = widget.previewCards.length;
    if (n == _base.length) return;

    setState(() => _base = List.generate(n, (i) => i));

    // The deck emptying mid-sequence leaves nothing to animate — hand off
    // rather than holding the player behind an empty stage.
    if (n == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    }
  }

  /// Guarded against firing twice AND against firing after this State is
  /// gone — either could otherwise happen if the sequence outlives a fast
  /// phase change (server moves on, this subtree is torn down before the
  /// controller completes).
  void _finish() {
    if (_completedOnce || !mounted) return;
    _completedOnce = true;
    widget.onComplete();
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.previewCards.length;
    if (n == 0) return const SizedBox.shrink();

    final ctrl = _ctrl;
    if (ctrl == null) {
      // Reduced motion: render the settled arrangement once. _finish() has
      // already been scheduled, so this is a single frame at most.
      return _stage(context, 1.0, n);
    }
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) => _stage(context, ctrl.value, n),
    );
  }

  Widget _stage(BuildContext context, double t, int n) {
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 10.0;
        const minCardW = 46.0;
        const maxCardW = 90.0;
        final cardW = ((box.maxWidth - gap * (n - 1)) / n).clamp(
          minCardW,
          maxCardW,
        );
        final cardH = cardW * (4.2 / 3);
        final totalW = n * cardW + (n - 1) * gap;
        final startX = ((box.maxWidth - totalW) / 2).clamp(
          0.0,
          double.infinity,
        );

        final move = DossierShuffleTimeline.completedMoves(t);
        final order = DossierShuffleTimeline.orderAt(n, move);

        // Paint order: during move 1 one dossier passes BEHIND another,
        // which is what makes the shuffle read as physical rather than as a
        // grid reflow. Sorting by zOrder is content-blind — it depends on
        // display position only.
        final drawOrder = List<int>.generate(n, (i) => i)
          ..sort((a, b) {
            final za = DossierShuffleTimeline.zOrder(
              order.indexOf(a),
              n,
              move,
              DossierShuffleTimeline.shuffleProgress(t),
            );
            final zb = DossierShuffleTimeline.zOrder(
              order.indexOf(b),
              n,
              move,
              DossierShuffleTimeline.shuffleProgress(t),
            );
            return za.compareTo(zb);
          });

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DossierCaption(stage: dossierStageAt(t)),
            const SizedBox(height: 12),
            SizedBox(
              height: cardH + 16,
              width: double.infinity,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final i in drawOrder)
                    _card(i, order, startX, cardW, cardH, gap, n, t),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _card(
    int i,
    List<int> order,
    double startX,
    double cardW,
    double cardH,
    double gap,
    int n,
    double t,
  ) {
    final displayPos = order.indexOf(i);
    final left = startX + displayPos * (cardW + gap);

    // Magician-flourish parameters: lift, tilt and a "pop" scale, all
    // computed only while THIS card is actually mid-move, and only from
    // display positions — never from card content (see the class doc
    // comment's leak-prevention contract).
    final sp = DossierShuffleTimeline.shuffleProgress(t);
    var lift = 0.0;
    var tilt = 0.0;
    var pop = 1.0;
    if (sp != null) {
      final bounds = DossierShuffleTimeline.moveBounds;
      for (var m = 1; m < bounds.length; m++) {
        if (sp >= bounds[m - 1] && sp < bounds[m]) {
          final local = (sp - bounds[m - 1]) / (bounds[m] - bounds[m - 1]);
          final fromPos = DossierShuffleTimeline.orderAt(n, m - 1).indexOf(i);
          final toPos = DossierShuffleTimeline.orderAt(n, m).indexOf(i);
          if (fromPos != toPos) {
            // A real card only ever travels while airborne — a magician
            // lifts it clear of the table, flicks it across with a visible
            // tilt, then sets it back down flat. The higher arc (up from
            // 14px) and the tilt (peaking mid-flight, gone at both ends)
            // are what turn a slide into a flourish.
            lift = DossierShuffleTimeline.liftFor(local);
            final direction = (toPos - fromPos).sign;
            tilt = DossierShuffleTimeline.tiltFor(local) * direction;
            pop = DossierShuffleTimeline.popFor(local);
          }
          break;
        }
      }
    }

    final entrance = DossierShuffleTimeline.entranceFor(displayPos, n, t);
    final fan = DossierShuffleTimeline.fanAngle(displayPos, n, t);
    final flip = DossierShuffleTimeline.flipProgress(t);

    return AnimatedPositioned(
      duration: sp == null ? Duration.zero : const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
      left: left,
      top: 8 - lift,
      width: cardW,
      height: cardH,
      child: Opacity(
        opacity: entrance,
        child: Transform.scale(
          scale: (0.92 + entrance * 0.08) * pop,
          child: Transform.rotate(
            angle: fan + tilt,
            child: Builder(
              builder: (context) {
                // Same face-up/face-down flip math as CardFlipReveal, run in
                // reverse (starts face up, ends face down).
                final angle = flip * math.pi;
                final isBack = angle > math.pi / 2;
                final display = isBack ? angle - math.pi : angle;
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateY(display),
                  child: isBack
                      ? ShuffleCardBack(
                          glowT: DossierShuffleTimeline.shuffleProgress(t),
                        )
                      : PlayerCard(card: widget.previewCards[i]),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── Slot grid ─────────────────────────────────────────────────────────────────

class _SlotGrid extends StatelessWidget {
  const _SlotGrid({
    required this.totalSlots,
    required this.availableSlots,
    required this.slotMeta,
    required this.isActivePicker,
    required this.isAvailable,
    this.pickedIndex,
    this.onPick,
    this.onCardTap,
  });

  final int totalSlots;
  final List<int> availableSlots;
  final List<HiddenSlotInfo> slotMeta;
  final bool isActivePicker;
  final bool Function(int) isAvailable;

  /// Slot the local player just tapped, while the resulting `pick_hidden_slot`
  /// is still in flight. Drives the lift/dim/seal-close feedback. Null until
  /// a tap happens; the server's next `game_state` replaces this whole grid.
  final int? pickedIndex;

  final ValueChanged<int>? onPick;
  final ValueChanged<CandidateCard>? onCardTap;

  HiddenSlotInfo? _metaFor(int index) {
    for (final s in slotMeta) {
      if (s.slotIndex == index) return s;
    }
    return null;
  }

  /// Maps grid booleans onto the dossier's visual state.
  ///
  /// Content-blind by construction: it reads only the slot index, whether
  /// this player is the active picker, and which index they just tapped —
  /// never anything about the card sealed inside.
  DossierState _stateFor(int i) {
    if (pickedIndex == i) return DossierState.locked;
    // Once a pick is in flight every other dossier goes quiet, so the chosen
    // one is unambiguous.
    if (pickedIndex != null) return DossierState.unavailable;
    if (!isActivePicker) return DossierState.resting;
    return DossierState.available;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        // At most 4 columns; cards at least 60 px wide.
        const gap = 8.0;
        final maxCols = totalSlots <= 3
            ? totalSlots
            : (totalSlots <= 6 ? 3 : 4);
        int cols = maxCols;
        for (; cols > 1; cols--) {
          final w = (box.maxWidth - gap * (cols - 1)) / cols;
          if (w >= 60) break;
        }
        final cardW = (box.maxWidth - gap * (cols - 1)) / cols;
        // Height matches PlayerCard's AspectRatio(3/4.2) so all slots align.
        final cardH = cardW * (4.2 / 3);

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          alignment: WrapAlignment.center,
          children: List.generate(totalSlots, (i) {
            final available = isAvailable(i);
            return SizedBox(
              width: cardW,
              height: cardH,
              child: available
                  ? _SlotCard(
                      slotNumber: i + 1,
                      isActivePicker: isActivePicker,
                      state: _stateFor(i),
                      onTap: isActivePicker && pickedIndex == null
                          ? () => onPick?.call(i)
                          : null,
                    )
                  : _TakenSlotCard(
                      meta: _metaFor(i),
                      slotNumber: i + 1,
                      onCardTap: onCardTap,
                    ),
            );
          }),
        );
      },
    );
  }
}

// ── Available slot card ───────────────────────────────────────────────────────

/// Rendered for slots that have NOT yet been picked.
/// Two visual states:
///   - active picker (tappable) — green border + "TAP TO PICK"
///   - waiting             — muted border, no call-to-action
/// Thin wrapper mapping this grid's booleans onto [DossierState].
///
/// **The pick is still a single tap.** `onPick` fires immediately, exactly as
/// it always has — [DossierState.selected] and [DossierState.locked] are
/// optimistic *feedback* for the pick already in flight, not a new
/// select-then-confirm gate. Adding a confirmation step would change the
/// game's interaction contract, which this batch explicitly must not do.
class _SlotCard extends StatelessWidget {
  const _SlotCard({
    required this.slotNumber,
    required this.isActivePicker,
    required this.state,
    this.onTap,
  });

  final int slotNumber;
  final bool isActivePicker;
  final DossierState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) =>
      SealedDossierCard(slotNumber: slotNumber, state: state, onTap: onTap);
}

// ── Taken slot card ───────────────────────────────────────────────────────────

/// Rendered for slots that have already been picked.
/// The card is always revealed to all players — shows card face + picker badge.
/// Tapping opens the card details modal when [meta.card] is present.
/// [meta] null is a defensive fallback only (should not occur in normal flow).
class _TakenSlotCard extends StatelessWidget {
  const _TakenSlotCard({
    required this.meta,
    required this.slotNumber,
    this.onCardTap,
  });

  final HiddenSlotInfo? meta;
  final int slotNumber;
  final ValueChanged<CandidateCard>? onCardTap;

  @override
  Widget build(BuildContext context) {
    final card = meta?.card;
    return GestureDetector(
      onTap: card != null ? () => onCardTap?.call(card) : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Card face (always shown once taken) ────────────────────────
            Positioned.fill(
              child: meta?.card != null
                  ? PlayerCard(card: meta!.card)
                  : const PlayerCard(faceDown: true),
            ),

            // ── Subtle dark gradient so the badge remains legible ──────────
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.05),
                      Colors.black.withValues(alpha: 0.50),
                    ],
                  ),
                ),
              ),
            ),

            // ── Picker badge at the bottom ──────────────────────────────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _PickerBadge(
                name: meta?.pickedByPlayerName,
                slotNumber: slotNumber,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Picker badge ──────────────────────────────────────────────────────────────

class _PickerBadge extends StatelessWidget {
  const _PickerBadge({required this.name, required this.slotNumber});

  final String? name;
  final int slotNumber;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.82)],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, color: HETheme.pfAccentViolet, size: 9),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              name != null ? 'Picked by $name' : 'Slot $slotNumber',
              style: const TextStyle(
                color: HETheme.pfTextPrimary,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          'No slots available',
          style: TextStyle(color: HETheme.pfTextSecondary, fontSize: 13),
        ),
      ),
    );
  }
}

// ── Card-flip reveal overlay ───────────────────────────────────────────────────
// Full-screen overlay with a FIFA-style card reveal animation.
// Fix: GestureDetector uses HitTestBehavior.opaque so the entire overlay
// surface catches taps — no hit-test fall-through to the board below.

class CardFlipReveal extends StatefulWidget {
  const CardFlipReveal({
    super.key,
    required this.card,
    required this.onDismiss,
  });

  final CandidateCard card;
  final VoidCallback onDismiss;

  @override
  State<CardFlipReveal> createState() => _CardFlipRevealState();
}

class _CardFlipRevealState extends State<CardFlipReveal>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  // Entrance: scale + fade (0 → 0.30 of timeline)
  late Animation<double> _scale;
  late Animation<double> _opacity;
  // Flip: 0 → π (0.25 → 1.0 of timeline, overlaps slightly with entrance end)
  late Animation<double> _flip;

  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.30, curve: Curves.easeOutBack),
      ),
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.25, curve: Curves.easeIn),
      ),
    );
    _flip = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.25, 1.0, curve: Curves.easeInOutCubic),
      ),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _dismiss() {
    // Block taps until animation finishes and prevent double-fire.
    if (_dismissed || !_ctrl.isCompleted) return;
    _dismissed = true;
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // opaque: the entire overlay surface catches taps — nothing bleeds through.
      behavior: HitTestBehavior.opaque,
      onTap: _dismiss,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.85),
        child: SizedBox.expand(
          child: Center(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                final flipAngle = _flip.value * math.pi;
                final isFront = flipAngle > math.pi / 2;
                // Mirror the second half so the card lands face-forward.
                final displayAngle = isFront ? flipAngle - math.pi : flipAngle;

                // Hint fades in over the last 5 % of the animation.
                final hintOpacity =
                    ((_ctrl.value - 0.95) / 0.05).clamp(0.0, 1.0) * 0.55;

                return Opacity(
                  opacity: _opacity.value,
                  child: Transform.scale(
                    scale: _scale.value,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.001)
                            ..rotateY(displayAngle),
                          child: SizedBox(
                            width: 224,
                            child: isFront
                                ? PlayerCard(card: widget.card)
                                : const PlayerCard(faceDown: true),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Opacity(
                          opacity: hintOpacity,
                          child: const Text(
                            'Tap anywhere to continue',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── (Card back and card front are now rendered via PlayerCard) ─────────────────
