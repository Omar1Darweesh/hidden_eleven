import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_motion.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/widgets/card_details_modal.dart';
import '../models/tournament_models.dart';
import 'fixture_capsule.dart';
import 'match_details_panel.dart';
import 'match_phase.dart';

// ---------------------------------------------------------------------------
// MatchCardWidget
// ---------------------------------------------------------------------------

class MatchCardWidget extends StatefulWidget {
  final MatchSnapshot match;
  final String? myParticipantId;
  final List<String> readyParticipantIds;
  final VoidCallback? onReady;
  final VoidCallback? onTap;
  final List<LiveMatchEvent> liveEvents;
  final TournamentMatchResult? completedResult;
  final String roundLabel;

  const MatchCardWidget({
    super.key,
    required this.match,
    required this.myParticipantId,
    required this.readyParticipantIds,
    this.onReady,
    this.onTap,
    required this.liveEvents,
    this.completedResult,
    this.roundLabel = '',
  });

  @override
  State<MatchCardWidget> createState() => _MatchCardWidgetState();
}

class _MatchCardWidgetState extends State<MatchCardWidget> {
  bool _readyPressed = false;
  // Accordion: full match details expand in-place (no separate route).
  late bool _expanded;
  // Once the user manually toggles, stop overriding their choice.
  bool _userToggled = false;

  // Details only exist once a match is live or finished.
  bool get _canExpand =>
      widget.match.status == 'simulating' || widget.match.status == 'complete';

  @override
  void initState() {
    super.initState();
    // A live match opens its details automatically — the score, minute, and
    // event feed must be visible without an extra tap.
    _expanded = widget.match.status == 'simulating';
  }

  @override
  void didUpdateWidget(MatchCardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-open the instant this match goes live, unless the user has already
    // made their own choice about this card.
    if (!_userToggled &&
        oldWidget.match.status != 'simulating' &&
        widget.match.status == 'simulating') {
      setState(() => _expanded = true);
    }
  }

  void _toggleExpanded() => setState(() {
    _userToggled = true;
    _expanded = !_expanded;
  });

  bool get _isMyMatch {
    final myId = widget.myParticipantId;
    if (myId == null) return false;
    return widget.match.participantA.participantId == myId ||
        widget.match.participantB.participantId == myId;
  }

  bool get _iAlreadyReady {
    final myId = widget.myParticipantId;
    if (myId == null) return false;
    return widget.readyParticipantIds.contains(myId);
  }

  // ── Per-team match facts (collapsed-state mini scoreboard) ─────────────────

  /// Goals/cards for one team, chronological — the events worth naming in the
  /// compact card (shots/big-chances stay counters-only inside the accordion).
  List<LiveMatchEvent> _teamMajorEvents(String participantId) {
    final events = widget.liveEvents
        .where(
          (e) =>
              e.teamParticipantId == participantId &&
              (e.type == 'goal' ||
                  e.type == 'yellow_card' ||
                  e.type == 'red_card'),
        )
        .toList();
    events.sort((x, y) => x.minute.compareTo(y.minute));
    return events;
  }

  // ── Scores ────────────────────────────────────────────────────────────────

  int get _scoreA => widget.liveEvents.isNotEmpty
      ? widget.liveEvents.last.currentScoreA
      : widget.completedResult?.scoreA ?? 0;

  int get _scoreB => widget.liveEvents.isNotEmpty
      ? widget.liveEvents.last.currentScoreB
      : widget.completedResult?.scoreB ?? 0;

  bool get _wasDecidedByPenalties =>
      widget.completedResult?.wasDecidedByPenalties ?? false;

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final a = widget.match.participantA;
    final b = widget.match.participantB;
    final status = widget.match.status;
    final showScore = status == 'simulating' || status == 'complete';

    final accentColor = switch (status) {
      'simulating' => HETheme.pfDanger,
      'ready_check' => HETheme.pfWarning,
      'complete' => HETheme.pfAccentViolet,
      _ => Colors.transparent,
    };

    // Pre-compute per-team event lines and ready states used in both columns.
    final aEvents = _teamMajorEvents(a.participantId);
    final bEvents = _teamMajorEvents(b.participantId);
    final aReady = widget.readyParticipantIds.contains(a.participantId);
    final bReady = widget.readyParticipantIds.contains(b.participantId);

    // Real kick-by-kick shootout tally — from the actual event stream, never
    // fabricated. Reused for both a live match still taking kicks and a
    // completed one (the cached events remain available), so the dot strip
    // stays meaningful after full time too.
    final shootout = computeShootoutTally(
      liveEvents: widget.liveEvents,
      participantAId: a.participantId,
      participantBId: b.participantId,
    );
    final reduceMotion = HEMotion.reduced(context);

    return GestureDetector(
      // Tapping an expandable card toggles the in-place details accordion.
      // (The old behaviour navigated to a separate broadcast route — removed.)
      onTap: _canExpand ? _toggleExpanded : widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        // The shared fixture surface, so a match reads as the same object
        // here and in the bracket. A live match is one of the reserved
        // "focus" surfaces — everything else stays at standard weight so the
        // live fixture is the one that leads. The status accent keeps its
        // established colour (passed through as `accent`) and still paints as
        // the clipped left strip below; a non-uniform Border cannot be
        // combined with a borderRadius in Flutter.
        // T3: the live match gets one restrained edge sweep — the single
        // continuous animation on this card, and the only "hot" element.
        child: _LiveEdgeSweep(
          active: status == 'simulating',
          color: accentColor,
          child: FixtureCapsule(
          accent: accentColor == Colors.transparent
              ? HETheme.pfBorder
              : accentColor,
          emphasis: status == 'simulating'
              ? FixtureEmphasis.focus
              : FixtureEmphasis.standard,
          padding: EdgeInsets.zero,
          child: ClipRRect(
          borderRadius: HEShape.md,
          // Stack instead of Row+IntrinsicHeight: the card's height is NOT
          // fixed — AnimatedSize below grows it when match details expand.
          // IntrinsicHeight computes the Row's height ONCE, before
          // AnimatedSize has finished animating to its target size, then
          // locks every Row child (including this Column) to that
          // now-stale height — a well-known Flutter footgun, and exactly
          // what produced the reproduced "209 pixels" overflow the moment
          // a live/complete match's details panel expanded. A Stack lets
          // the Column size itself naturally (AnimatedSize free to grow),
          // with the accent bar simply overlaid via Positioned instead of
          // needing to literally match a sibling's height.
          child: Stack(
            children: [
              // Left padding matches the old accent bar's 4px width exactly,
              // so content lines up identically now that the bar is an
              // overlay instead of a real layout sibling.
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Card header: round label + status badge ───────────────────
                    _CardHeader(
                      roundLabel: widget.roundLabel,
                      status: status,
                      phase: computeMatchPhase(
                        match: widget.match,
                        liveEvents: widget.liveEvents,
                        completedResult: widget.completedResult,
                      ),
                    ),

                    // ── Score / VS row ────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left team — name, rating, facts, ready status
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ParticipantHeader(
                                  participant: a,
                                  isRightSide: false,
                                ),
                                Text(
                                  '★ ${a.overallRating.toStringAsFixed(1)}',
                                  style: const TextStyle(
                                    color: HETheme.pfGold,
                                    fontSize: 11,
                                  ),
                                ),
                                if (showScore) ...[
                                  const SizedBox(height: 6),
                                  _TeamMatchFacts(
                                    events: aEvents,
                                    align: CrossAxisAlignment.start,
                                  ),
                                ],
                                if (status == 'ready_check') ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    aReady ? '✓ Ready' : '⌛ Not ready',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: aReady
                                          ? HETheme.pfSuccess
                                          : Colors.white38,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),

                          // Centre
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (showScore)
                                  AnimatedSwitcher(
                                    duration: reduceMotion
                                        ? Duration.zero
                                        : const Duration(milliseconds: 400),
                                    transitionBuilder: (child, animation) =>
                                        ScaleTransition(
                                          scale: CurvedAnimation(
                                            parent: animation,
                                            curve: Curves.elasticOut,
                                          ),
                                          child: FadeTransition(
                                            opacity: animation,
                                            child: child,
                                          ),
                                        ),
                                    child: Text(
                                      '$_scoreA  —  $_scoreB',
                                      key: ValueKey('${_scoreA}_$_scoreB'),
                                      style: const TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  )
                                else
                                  const Text(
                                    'vs',
                                    style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 16,
                                    ),
                                  ),
                                // Real-football style penalty result, e.g. "(4–3 pens)".
                                if (showScore && _wasDecidedByPenalties)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      '(${widget.completedResult!.penaltyScoreA}–'
                                      '${widget.completedResult!.penaltyScoreB} pens)',
                                      style: const TextStyle(
                                        color: HETheme.pfGold,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          // Right team — name, rating, facts, ready status
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                ParticipantHeader(
                                  participant: b,
                                  isRightSide: true,
                                ),
                                Text(
                                  '★ ${b.overallRating.toStringAsFixed(1)}',
                                  style: const TextStyle(
                                    color: HETheme.pfGold,
                                    fontSize: 11,
                                  ),
                                ),
                                if (showScore) ...[
                                  const SizedBox(height: 6),
                                  _TeamMatchFacts(
                                    events: bEvents,
                                    align: CrossAxisAlignment.end,
                                  ),
                                ],
                                if (status == 'ready_check') ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    bReady ? '✓ Ready' : '⌛ Not ready',
                                    textAlign: TextAlign.end,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: bReady
                                          ? HETheme.pfSuccess
                                          : Colors.white38,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Penalty shootout strip — real kick-by-kick tally ──────────
                    if (shootout.hasStarted) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: _PenaltyShootoutStrip(shootout: shootout),
                      ),
                    ],

                    const SizedBox(height: 10),

                    // ── Winner banner (complete only) ─────────────────────────────
                    if (status == 'complete' && widget.match.winnerId != null)
                      _WinnerBanner(match: widget.match),

                    // ── Ready button (my match, ready_check only) ─────────────────
                    if (status == 'ready_check' && _isMyMatch)
                      _buildReadyButton(),

                    // ── In-place details accordion ────────────────────────────────
                    if (_canExpand)
                      _buildExpandToggle()
                    else
                      const SizedBox(height: 12),
                    AnimatedSize(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      alignment: Alignment.topCenter,
                      child: (_expanded && _canExpand)
                          ? MatchDetailsPanel(
                              match: widget.match,
                              liveEvents: widget.liveEvents,
                              completedResult: widget.completedResult,
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                  ],
                ),
              ),
              // Status-coloured left accent bar (full card height) —
              // overlaid instead of a real Row sibling; see the comment
              // above this Stack for why.
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 4,
                child: Container(color: accentColor),
              ),
            ],
          ),
          ),
          ),
        ),
      ),
    );
  }

  // ── Accordion toggle ────────────────────────────────────────────────────────

  Widget _buildExpandToggle() {
    return InkWell(
      onTap: _toggleExpanded,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _expanded ? 'HIDE DETAILS' : 'WATCH DETAILS',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 10,
                letterSpacing: 1.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              _expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: Colors.white38,
            ),
          ],
        ),
      ),
    );
  }

  // ── Ready button (standalone — status row is now inline in the columns) ──────

  Widget _buildReadyButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
      child: !_iAlreadyReady && !_readyPressed
          ? SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() => _readyPressed = true);
                  widget.onReady?.call();
                },
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Ready ✓'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: HETheme.pfSuccess,
                  foregroundColor: Colors.black,
                ),
              ),
            )
          : Text(
              _iAlreadyReady
                  ? 'Waiting for opponent...'
                  : 'Ready! Waiting for opponent...',
              style: const TextStyle(
                color: Colors.white54,
                fontStyle: FontStyle.italic,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// _CardHeader — thin top bar with round label + status badge
// ---------------------------------------------------------------------------

class _CardHeader extends StatelessWidget {
  final String roundLabel;
  final String status;
  final MatchPhaseInfo phase;

  const _CardHeader({
    required this.roundLabel,
    required this.status,
    required this.phase,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(HEShape.rMd),
        ),
      ),
      child: Row(
        children: [
          Text(
            roundLabel.toUpperCase(),
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          _StatusBadge(status: status, phase: phase),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _StatusBadge — READY CHECK / pulsing LIVE (1H/2H/Pens) / FT (incl. Pens)
// ---------------------------------------------------------------------------

class _StatusBadge extends StatelessWidget {
  final String status;
  final MatchPhaseInfo phase;
  const _StatusBadge({required this.status, required this.phase});

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      'ready_check' => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: HETheme.pfWarning.withValues(alpha: 0.15),
          borderRadius: HEShape.sm,
          border: Border.all(color: HETheme.pfWarning.withValues(alpha: 0.6)),
        ),
        child: const Text(
          'READY CHECK',
          style: TextStyle(
            color: HETheme.pfWarning,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ),
      // Phase already reads e.g. "1H · 62'" / "Pens · Live" — the pulsing
      // dot itself communicates "live", so it isn't repeated in the text.
      'simulating' => _PulsingBadge(
        label: phase.compact,
        color: HETheme.pfDanger,
      ),
      // Phase reads "FT" or "FT · Pens" — never a bare "FULL TIME" that
      // hides how the match was actually decided.
      'complete' => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: HETheme.pfAccentViolet.withValues(alpha: 0.15),
          borderRadius: HEShape.sm,
          border: Border.all(color: HETheme.pfAccentViolet.withValues(alpha: 0.5)),
        ),
        child: Text(
          phase.compact.toUpperCase(),
          style: const TextStyle(
            color: HETheme.pfAccentViolet,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

// ---------------------------------------------------------------------------
// _PulsingBadge — animated green dot + label (same pattern as LiveBroadcast)
// ---------------------------------------------------------------------------

class _PulsingBadge extends StatefulWidget {
  final String label;
  final Color color;

  const _PulsingBadge({required this.label, required this.color});

  @override
  State<_PulsingBadge> createState() => _PulsingBadgeState();
}

class _PulsingBadgeState extends State<_PulsingBadge> {
  // Stage 3 / T3: this badge no longer runs its own loop.
  //
  // The live treatment is now the card's single edge sweep (see
  // `_LiveEdgeSweep`). Keeping this badge's own 900ms pulse as well would put
  // two continuously-pulsing elements on one card — exactly the "multiple
  // pulsing elements" the motion contract rules out, and a second continuous
  // animation on a screen that is only allowed one.
  //
  // Nothing is lost: the badge still renders at full intensity (t = 1.0) with
  // its colour, icon and "LIVE" text, which is what actually communicates the
  // state. It simply holds still while the card edge carries the motion. This
  // also means it behaves identically with and without reduced motion.
  @override
  Widget build(BuildContext context) => _buildBadge(1.0);

  Widget _buildBadge(double t) {
    final bg = Color.lerp(
      widget.color.withValues(alpha: 0.12),
      widget.color.withValues(alpha: 0.30),
      t,
    )!;
    final border = Color.lerp(
      widget.color.withValues(alpha: 0.4),
      widget.color,
      t,
    )!;
    final dot = Color.lerp(widget.color.withValues(alpha: 0.5), widget.color, t)!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: HEShape.sm,
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            widget.label,
            style: TextStyle(
              color: widget.color,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _WinnerBanner — amber "advances" strip
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// ParticipantHeader — reusable, side-aware identity block (logo + name + CPU
// badge) shared by both sides of a match-up. Mirrored left ↔ right so each
// side's identity anchors to its own outer edge and the two sides frame the
// centred score symmetrically, instead of a bare name drifting toward the
// middle on whichever side lacks a logo/CPU badge to anchor it.
// ---------------------------------------------------------------------------

class ParticipantHeader extends StatelessWidget {
  const ParticipantHeader({
    super.key,
    required this.participant,
    required this.isRightSide,
  });

  final ParticipantSnapshot participant;

  /// True for the right-hand participant — mirrors child order so the block
  /// hugs the far right edge exactly as the left side hugs the far left.
  final bool isRightSide;

  @override
  Widget build(BuildContext context) {
    final name = Flexible(
      child: Text(
        participant.displayName,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );

    // No logo/CPU badge to mirror — `mainAxisSize.min` is what actually pins
    // the block to its own edge (the parent Column's cross-axis alignment
    // does the rest); a plain unconstrained Row would default to filling the
    // whole half-width column and always render left-aligned regardless of
    // side, which was the original bug.
    if (!participant.isAi) {
      return Row(mainAxisSize: MainAxisSize.min, children: [name]);
    }

    final logo = CardLogoWidget(
      name: participant.displayName,
      size: 16,
      logoUrl: participant.clubLogoUrl,
      accentColor: HETheme.pfAccentViolet,
    );
    const cpuTag = _CpuTag();
    const gap = SizedBox(width: 5);

    // Left reads logo → name → CPU (natural reading order, hugging left);
    // right is the exact mirror, CPU → name → logo (hugging right) — a true
    // mirror image so both sides frame the score cleanly.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: isRightSide
          ? [cpuTag, gap, name, gap, logo]
          : [logo, gap, name, gap, cpuTag],
    );
  }
}

/// Small "CPU" marker distinguishing an AI-controlled club from a real
/// manager's team, without relying on color alone.
class _CpuTag extends StatelessWidget {
  const _CpuTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: HETheme.pfAccentViolet.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: HETheme.pfAccentViolet.withValues(alpha: 0.5)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.smart_toy_rounded, size: 9, color: HETheme.pfAccentViolet),
          SizedBox(width: 2),
          Text(
            'CPU',
            style: TextStyle(
              color: HETheme.pfAccentViolet,
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _WinnerBanner extends StatelessWidget {
  final MatchSnapshot match;

  const _WinnerBanner({required this.match});

  @override
  Widget build(BuildContext context) {
    final a = match.participantA;
    final b = match.participantB;
    final winner = match.winnerId == a.participantId ? a : b;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: HETheme.pfSuccess.withValues(alpha: 0.08),
        borderRadius: HEShape.sm,
        border: Border.all(color: HETheme.pfSuccess.withValues(alpha: 0.30)),
      ),
      child: Center(
        child: Text(
          '${winner.displayName} advances',
          style: const TextStyle(
            color: HETheme.pfSuccess,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _PenaltyShootoutStrip — compact kick-by-kick tally, mirrored left/right
// around the running score so it frames the card the same way the team
// identities do. Built only from real penalty_scored/penalty_missed events
// (see PenaltyShootoutTally) — every dot is a kick that actually happened;
// nothing is padded to a fixed count since sudden death is open-ended.
// ---------------------------------------------------------------------------

class _PenaltyShootoutStrip extends StatelessWidget {
  const _PenaltyShootoutStrip({required this.shootout});

  final PenaltyShootoutTally shootout;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: HETheme.pfGold.withValues(alpha: 0.06),
        borderRadius: HEShape.sm,
        border: Border.all(color: HETheme.pfGold.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                for (final scored in shootout.kicksA)
                  _PenaltyDot(scored: scored),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'PENS ${shootout.scoreA}–${shootout.scoreB}',
              style: const TextStyle(
                color: HETheme.pfGold,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final scored in shootout.kicksB)
                  _PenaltyDot(scored: scored),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PenaltyDot extends StatelessWidget {
  const _PenaltyDot({required this.scored});

  /// true = scored, false = missed. Only realized kicks are ever rendered —
  /// there is no "pending" dot, since an open-ended sudden death has no
  /// knowable total to pad toward.
  final bool scored;

  @override
  Widget build(BuildContext context) {
    final color = scored ? HETheme.pfSuccess : HETheme.pfDanger;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scored ? color : Colors.transparent,
          border: Border.all(color: color, width: 1.4),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _MiniStatColumn — per-team event facts, non-zero only
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// _TeamMatchFacts — real match-center style mini summary for one team, shown
// in the collapsed card: "Salah 12' (A: Trezeguet)", "Hegazi 37' YC", etc.
// Capped so a busy match still reads cleanly.
// ---------------------------------------------------------------------------

class _TeamMatchFacts extends StatelessWidget {
  static const int _maxLines = 4;

  final List<LiveMatchEvent> events;
  final CrossAxisAlignment align;

  const _TeamMatchFacts({required this.events, required this.align});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Text(
        'No events yet',
        style: TextStyle(color: Colors.white24, fontSize: 10),
      );
    }

    final shown = events.take(_maxLines).toList();
    final overflow = events.length - shown.length;

    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in shown) _eventLine(e),
        if (overflow > 0)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              '+$overflow more',
              style: const TextStyle(color: Colors.white24, fontSize: 10),
            ),
          ),
      ],
    );
  }

  Widget _eventLine(LiveMatchEvent e) {
    final (icon, color) = switch (e.type) {
      'goal' => ('⚽', HETheme.pfSuccess),
      'yellow_card' => ('🟨', HETheme.pfWarning),
      'red_card' => ('🟥', HETheme.pfDanger),
      _ => ('•', Colors.white38),
    };

    final suffix = switch (e.type) {
      'goal' =>
        (e.assistPlayerName != null && e.assistPlayerName!.isNotEmpty)
            ? ' (A: ${e.assistPlayerName})'
            : '',
      'yellow_card' => ' YC',
      'red_card' => ' RC',
      _ => '',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 10)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              "${e.playerName} ${e.minute}'$suffix",
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// T3: the live match's single continuous treatment — a soft accent glow that
/// breathes around the card's edge.
///
/// Rules this satisfies:
///  * **One hot thing.** This is the only looping animation on a live card;
///    `_PulsingBadge` deliberately holds still so the two don't compete.
///  * **Never blocks input.** It is a `DecoratedBox` behind the card with no
///    gesture handling, so taps pass straight through to the card and its
///    expand/ready controls throughout.
///  * **Reduced motion.** No controller is constructed at all; the glow is
///    painted once at its resting strength, so the card still reads as live.
class _LiveEdgeSweep extends StatefulWidget {
  const _LiveEdgeSweep({
    required this.active,
    required this.color,
    required this.child,
  });

  final bool active;
  final Color color;
  final Widget child;

  @override
  State<_LiveEdgeSweep> createState() => _LiveEdgeSweepState();
}

class _LiveEdgeSweepState extends State<_LiveEdgeSweep>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_LiveEdgeSweep old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  /// Starts the loop only while the match is actually live, and tears it down
  /// the moment it isn't — a finished match must not keep a ticker alive.
  void _sync() {
    if (!widget.active || HEMotion.reduced(context)) {
      _ctrl?.dispose();
      _ctrl = null;
      return;
    }
    if (_ctrl != null) return;
    _ctrl = AnimationController(vsync: this, duration: HEMotion.pulse)
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;

    final ctrl = _ctrl;
    if (ctrl == null) return _glow(0.5, widget.child);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: ctrl,
        builder: (context, child) => _glow(ctrl.value, child!),
        child: widget.child,
      ),
    );
  }

  Widget _glow(double t, Widget child) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: HEShape.md,
      boxShadow: [
        BoxShadow(
          color: widget.color.withValues(alpha: 0.10 + 0.16 * t),
          blurRadius: 14 + 12 * t,
          spreadRadius: 1,
        ),
      ],
    ),
    child: child,
  );
}
