import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_motion.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/widgets/card_details_modal.dart';
import 'package:hidden_eleven/features/tournament/widgets/fixture_capsule.dart';
import 'package:hidden_eleven/shared/widgets/rank_medallion.dart';
import '../models/tournament_models.dart';

/// A knockout bracket. At desktop widths (≥[HETheme.breakpointMobile]): a
/// centred layout where the trophy sits in the exact horizontal/vertical
/// centre, the left half feeds the final from the left, the right half
/// mirrors it, and connector lines join each slot to its parent. Below that
/// width: a horizontally-scrolling strip, one round per full-height column
/// (final round last) — the same halves/mirroring trick doesn't fit a narrow
/// phone, so narrow width gets its own honest linear layout instead of a
/// shrunk copy of the desktop one. Works for 4-team (2 rounds) and 8-team
/// (3 rounds) brackets in both layouts.
class TournamentBracketWidget extends StatefulWidget {
  final TournamentStateModel state;

  const TournamentBracketWidget({super.key, required this.state});

  @override
  State<TournamentBracketWidget> createState() =>
      _TournamentBracketWidgetState();
}

class _TournamentBracketWidgetState extends State<TournamentBracketWidget>
    with TickerProviderStateMixin {
  /// T4: the connector-fill for a match that has just been decided.
  ///
  /// Null whenever nothing is advancing — which is the normal state. Built
  /// only when a match's status is observed flipping to `complete` **while
  /// this widget is already mounted**; a fresh mount onto an
  /// already-finished bracket never animates, so re-entering the screen or
  /// reconnecting shows the settled bracket rather than replaying history.
  AnimationController? _advance;

  /// The match currently being animated, so a repeated `game_state`
  /// broadcast for the same match cannot restart the fill.
  String? _advancingMatchId;

  /// Every match id already seen as complete. Seeded on first build so an
  /// initial mount is never treated as a transition.
  final Set<String> _completedSeen = <String>{};
  bool _seeded = false;

  /// T1: the draw reveal. Runs at most once per mount, only when this widget
  /// is first shown during the bracket-reveal phase — arriving at a bracket
  /// that is already past the draw shows it settled.
  AnimationController? _drawReveal;
  bool _drawRevealPlayed = false;

  TournamentStateModel get state => widget.state;

  // The lucky draw: while the bracket-reveal phase is live, round-1 slots
  // briefly "spin" through the field before settling on the real, already
  // server-decided name (see GameService.beginTournament's shuffle) — a
  // cosmetic reveal only, never re-deciding the assignment itself.
  bool get _isDrawing => state.phase == TournamentPhase.bracketReveal;

  List<String> get _revealPool => _isDrawing && state.rounds.isNotEmpty
      ? state.rounds.first.matches
            .expand((m) => [m.participantA, m.participantB])
            .where((p) => p.participantId.isNotEmpty)
            .map((p) => p.displayName)
            .toList()
      : const <String>[];

  Iterable<MatchSnapshot> get _allMatches =>
      state.rounds.expand((r) => r.matches);

  @override
  void initState() {
    super.initState();
    _seedCompleted();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_drawRevealPlayed || !_isDrawing) return;
    _drawRevealPlayed = true;
    if (HEMotion.reduced(context)) return;
    _drawReveal = AnimationController(vsync: this, duration: HEMotion.entrance)
      ..forward();
  }

  /// Records what is already finished without animating any of it.
  void _seedCompleted() {
    for (final m in _allMatches) {
      if (m.status == 'complete') _completedSeen.add(m.matchId);
    }
    _seeded = true;
  }

  @override
  void didUpdateWidget(TournamentBracketWidget old) {
    super.didUpdateWidget(old);
    if (!_seeded) {
      _seedCompleted();
      return;
    }

    // Presentation-only diff of data this widget already receives: which
    // match newly reads as complete. Nothing here decides or advances a
    // match — the server has already done that, and this only notices.
    MatchSnapshot? newlyComplete;
    for (final m in _allMatches) {
      if (m.status == 'complete' && !_completedSeen.contains(m.matchId)) {
        _completedSeen.add(m.matchId);
        newlyComplete ??= m;
      }
    }
    if (newlyComplete == null) return;
    // Already animating this one — a repeat broadcast must not restart it.
    if (_advancingMatchId == newlyComplete.matchId) return;

    if (HEMotion.reduced(context)) return;

    _advance?.dispose();
    _advancingMatchId = newlyComplete.matchId;
    _advance = AnimationController(vsync: this, duration: HEMotion.wake)
      ..addStatusListener((s) {
        // Clear once settled so the bracket returns to its resting paint.
        if (s == AnimationStatus.completed && mounted) {
          setState(() => _advancingMatchId = null);
        }
      })
      ..forward();
    setState(() {});
  }

  @override
  void dispose() {
    _advance?.dispose();
    _drawReveal?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < HETheme.breakpointMobile) {
          return _MobileBracketStrip(
            state: state,
            isDrawing: _isDrawing,
            revealPool: _revealPool,
            drawReveal: _drawReveal,
          );
        }
        return _DesktopBracket(
          state: state,
          isDrawing: _isDrawing,
          revealPool: _revealPool,
          advance: _advancingMatchId == null ? null : _advance,
          advancingMatchId: _advancingMatchId,
          drawReveal: _drawReveal,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Desktop — centred halves + trophy, unchanged from before Phase B.
// ---------------------------------------------------------------------------

class _DesktopBracket extends StatelessWidget {
  final TournamentStateModel state;
  final bool isDrawing;
  final List<String> revealPool;

  /// T4: drives the advancing connector's fill. Null when nothing is
  /// advancing, which is the resting case.
  final AnimationController? advance;
  final String? advancingMatchId;

  /// T1: drives the staggered draw reveal. Null when the draw is not being
  /// revealed right now.
  final AnimationController? drawReveal;

  const _DesktopBracket({
    required this.state,
    required this.isDrawing,
    required this.revealPool,
    this.advance,
    this.advancingMatchId,
    this.drawReveal,
  });

  @override
  Widget build(BuildContext context) {
    final totalRounds = state.totalRounds;
    final bracketHeight = totalRounds == 2 ? 260.0 : 380.0;

    return SizedBox(
      height: bracketHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          // The centre is the point of the whole bracket, so it gets real
          // width rather than the 80px sliver it used to have — enough for a
          // readable trophy, two full finalist names and a VS rule.
          //
          // It can only take width the halves don't need, though: each half
          // has a real minimum below which its slot cards overflow. So the
          // centre grows into whatever is spare and falls back toward its old
          // narrow form at the 700px boundary, rather than squeezing the
          // halves.
          const minSideWidth = 300.0;
          // Each half also has a *maximum*: past this, a fixture capsule stops
          // being a capsule and inflates into a bar with the name at one end
          // and the rating stranded at the other — which is exactly how the
          // bracket read on a 1920px screen before the hub gained its max
          // width. Anything wider than the halves and centre need becomes
          // breathing room around the whole bracket instead of stretch inside
          // it.
          const maxSideWidth = 400.0;
          final spare = w - (minSideWidth * 2);
          final desiredCentre = w >= 900 ? 300.0 : 200.0;
          final centreWidth = spare <= 80.0
              ? 80.0
              : spare < desiredCentre
              ? spare
              : desiredCentre;
          final sideWidth = ((w - centreWidth) / 2).clamp(0.0, maxSideWidth);
          // Re-centre the trio when the halves are capped, so the Trophy
          // Centre stays on the bracket's true midline.
          final leftInset = (w - (sideWidth * 2 + centreWidth)) / 2;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: leftInset,
                top: 0,
                width: sideWidth,
                height: h,
                child: _BracketHalf(
                  state: state,
                  isLeft: true,
                  totalRounds: totalRounds,
                  isDrawing: isDrawing,
                  revealPool: revealPool,
                  advance: advance,
                  advancingMatchId: advancingMatchId,
                  drawReveal: drawReveal,
                ),
              ),
              Positioned(
                right: leftInset,
                top: 0,
                width: sideWidth,
                height: h,
                child: _BracketHalf(
                  state: state,
                  isLeft: false,
                  totalRounds: totalRounds,
                  isDrawing: isDrawing,
                  revealPool: revealPool,
                  advance: advance,
                  advancingMatchId: advancingMatchId,
                  drawReveal: drawReveal,
                ),
              ),
              Positioned(
                left: leftInset + sideWidth,
                width: centreWidth,
                top: 0,
                height: h,
                child: _TrophyCentre(state: state),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BracketHalf extends StatelessWidget {
  final TournamentStateModel state;
  final bool isLeft;
  final int totalRounds;
  final bool isDrawing;
  final List<String> revealPool;

  /// T4: non-null only while a connector in this half is filling.
  final AnimationController? advance;
  final String? advancingMatchId;

  /// T1: non-null only while the draw reveal is playing.
  final AnimationController? drawReveal;

  const _BracketHalf({
    required this.state,
    required this.isLeft,
    required this.totalRounds,
    this.isDrawing = false,
    this.revealPool = const [],
    this.advance,
    this.advancingMatchId,
    this.drawReveal,
  });

  /// Rounds for this half, outermost (earliest) → innermost. Left side takes
  /// the first half of each round's matches; right side the second half. The
  /// final round is dropped — it lives in the trophy centre.
  List<List<MatchSnapshot>> _getRoundMatches() {
    final result = <List<MatchSnapshot>>[];
    for (final round in state.rounds) {
      final matches = round.matches;
      final half = matches.length ~/ 2;
      if (isLeft) {
        result.add(matches.sublist(0, half == 0 ? matches.length : half));
      } else {
        result.add(half == 0 ? <MatchSnapshot>[] : matches.sublist(half));
      }
    }
    if (result.isNotEmpty) result.removeLast(); // final → trophy centre
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final roundMatches = _getRoundMatches();
    if (roundMatches.isEmpty || roundMatches.every((r) => r.isEmpty)) {
      return const SizedBox.shrink();
    }

    // T4: locate the advancing match within this half, so only its connector
    // is highlighted. Returns null on the half that doesn't contain it, which
    // is how "only the changed segment animates" is enforced structurally
    // rather than by convention.
    ({int round, int match})? advancingCell;
    if (advancingMatchId != null) {
      for (var r = 0; r < roundMatches.length; r++) {
        final i = roundMatches[r].indexWhere(
          (m) => m.matchId == advancingMatchId,
        );
        if (i >= 0) {
          advancingCell = (round: r, match: i);
          break;
        }
      }
    }

    final painter = CustomPaint(
      painter: _BracketLinePainter(
        roundCount: roundMatches.length,
        isLeft: isLeft,
        advancing: advancingCell,
        progress: advancingCell == null ? 0.0 : (advance?.value ?? 0.0),
      ),
      child: Row(
        // Left half: outermost round on the left, innermost nearest the trophy.
        // Right half mirrors it via RTL so the innermost sits nearest the trophy.
        textDirection: isLeft ? TextDirection.ltr : TextDirection.rtl,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int ri = 0; ri < roundMatches.length; ri++)
            Expanded(
              // T1: columns settle in outermost-first, so the draw reads as
              // filling toward the final.
              child: BracketStaggerIn(
                controller: drawReveal,
                order: ri,
                total: roundMatches.length,
                child: _RoundColumn(
                  matches: roundMatches[ri],
                  // Round 1 (outermost, ri == 0) is the only round with a
                  // real draw to reveal — later rounds are genuinely TBD.
                  isDrawing: isDrawing && ri == 0,
                  revealPool: revealPool,
                ),
              ),
            ),
        ],
      ),
    );

    // Only repaint on the half that actually contains the advancing match;
    // the other half returns its static painter untouched.
    final controller = advance;
    if (advancingCell == null || controller == null) return painter;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => CustomPaint(
          painter: _BracketLinePainter(
            roundCount: roundMatches.length,
            isLeft: isLeft,
            advancing: advancingCell,
            progress: HEMotion.easeOut.transform(controller.value),
          ),
          child: painter.child,
        ),
      ),
    );
  }
}

class _RoundColumn extends StatelessWidget {
  final List<MatchSnapshot> matches;
  final bool isDrawing;
  final List<String> revealPool;

  const _RoundColumn({
    required this.matches,
    this.isDrawing = false,
    this.revealPool = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: matches
          .map(
            (m) => _BracketMatchBlock(
              match: m,
              isDrawing: isDrawing,
              revealPool: revealPool,
            ),
          )
          .toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared match/slot rendering — used by both the desktop halves and the
// mobile strip, so a slot's state treatment can never drift between layouts.
// ---------------------------------------------------------------------------

class _BracketMatchBlock extends StatelessWidget {
  final MatchSnapshot match;
  final bool isDrawing;
  final List<String> revealPool;

  const _BracketMatchBlock({
    required this.match,
    this.isDrawing = false,
    this.revealPool = const [],
  });

  @override
  Widget build(BuildContext context) {
    final isWinnerA = match.winnerId == match.participantA.participantId;
    final isWinnerB = match.winnerId == match.participantB.participantId;
    final isComplete = match.status == 'complete';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BracketSlotCard(
            participant: match.participantA,
            isWinner: isWinnerA,
            isEliminated: isComplete && !isWinnerA,
            matchStatus: match.status,
            isDrawing: isDrawing,
            revealPool: revealPool,
          ),
          const SizedBox(height: 3),
          _BracketSlotCard(
            participant: match.participantB,
            isWinner: isWinnerB,
            isEliminated: isComplete && !isWinnerB,
            matchStatus: match.status,
            isDrawing: isDrawing,
            revealPool: revealPool,
          ),
        ],
      ),
    );
  }
}

/// Fixed per-block height budget (two 42px slot cards + the 3px gap between
/// them) — used by the mobile strip to size its columns so every round's
/// matches stack with a predictable, readable height regardless of round.
const double kBracketMatchBlockHeight = 42 * 2 + 3;

class _BracketSlotCard extends StatelessWidget {
  final ParticipantSnapshot participant;
  final bool isWinner;
  final bool isEliminated;

  /// Raw match status ('ready_check' | 'simulating' | 'complete') — drives
  /// the "Scheduled" (known, not yet started) and "Live" (static, no pulse —
  /// the animated version is Phase C) tags on an otherwise-plain slot.
  final String matchStatus;

  final bool isDrawing;
  final List<String> revealPool;

  const _BracketSlotCard({
    required this.participant,
    required this.isWinner,
    required this.isEliminated,
    required this.matchStatus,
    this.isDrawing = false,
    this.revealPool = const [],
  });

  /// Genuinely unknown — no participant has been assigned this slot yet.
  /// Kept intentionally neutral (never a guessed or placeholder identity):
  /// safeguard from the approved Phase B plan.
  bool get _isTbd =>
      participant.participantId.isEmpty || participant.overallRating == 0.0;

  @override
  Widget build(BuildContext context) {
    if (_isTbd) {
      return Container(
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: HETheme.pfSurfaceRaised,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white12),
        ),
        child: const Text(
          'TBD',
          style: TextStyle(color: Colors.white24, fontSize: 10),
        ),
      );
    }

    final name = participant.displayName.length > 12
        ? '${participant.displayName.substring(0, 11)}…'
        : participant.displayName;

    if (isEliminated) {
      // Explicit label/icon in addition to dimming — state must never rest
      // on opacity alone.
      return Opacity(
        opacity: 0.3,
        child: _card(
          name,
          Colors.white24,
          Colors.white38,
          Colors.white54,
          tag: const _SlotTag(
            label: 'OUT',
            color: Colors.white38,
            icon: Icons.close_rounded,
          ),
        ),
      );
    }

    if (isWinner) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: HETheme.pfAccentViolet.withValues(alpha: 0.35),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: _card(
          name,
          HETheme.pfAccentViolet,
          HETheme.pfAccentViolet,
          HETheme.pfGold,
          isWinner: true,
        ),
      );
    }

    // Known, not-yet-decided participant: static "Live" or "Scheduled" tag —
    // never conveyed by color alone, and never implying a live pulse (that
    // animation is explicitly Phase C).
    final Widget? tag;
    final Color borderColor;
    if (matchStatus == 'simulating') {
      tag = const _SlotTag(
        label: 'LIVE',
        color: HETheme.pfDanger,
        icon: Icons.podcasts_rounded,
      );
      borderColor = HETheme.pfDanger.withValues(alpha: 0.55);
    } else if (matchStatus == 'ready_check') {
      tag = const _SlotTag(
        label: 'NEXT',
        color: HETheme.pfAccentVioletGlow,
        icon: Icons.schedule_rounded,
      );
      borderColor = Colors.white24;
    } else {
      tag = null;
      borderColor = Colors.white24;
    }

    return _card(
      name,
      borderColor,
      Colors.white,
      HETheme.pfGold,
      revealing: isDrawing && revealPool.isNotEmpty,
      tag: tag,
    );
  }

  Widget _card(
    String name,
    Color borderColor,
    Color nameColor,
    Color ratingColor, {
    bool isWinner = false,
    bool revealing = false,
    Widget? tag,
  }) {
    // A real club badge for the AI side — hidden mid-reveal since the name
    // itself is still cycling through the shuffle at that point.
    final showAiBadge = participant.isAi && !revealing;
    final card = Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: isWinner
            ? HETheme.pfAccentViolet.withValues(alpha: 0.14)
            : HETheme.pfSurfaceRaised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: isWinner ? 1.5 : 1),
      ),
      child: Row(
        children: [
          if (isWinner)
            const Padding(
              padding: EdgeInsets.only(right: 3),
              child: Text(
                '✓',
                style: TextStyle(color: HETheme.pfAccentViolet, fontSize: 10),
              ),
            ),
          if (showAiBadge) ...[
            CardLogoWidget(
              name: name,
              size: 14,
              logoUrl: participant.clubLogoUrl,
              accentColor: nameColor,
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: revealing
                ? _ShuffleRevealText(
                    finalName: name,
                    pool: revealPool,
                    // A small deterministic per-slot stagger (based on the
                    // participant's own id) so slots don't all lock in on the
                    // exact same frame — reads as a wheel settling, not a
                    // synchronized flash.
                    duration: Duration(
                      milliseconds:
                          700 +
                          (participant.participantId.hashCode.abs() % 500),
                    ),
                    style: TextStyle(
                      color: nameColor,
                      fontSize: 11,
                      fontWeight: isWinner
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  )
                : Text(
                    name,
                    style: TextStyle(
                      color: nameColor,
                      fontSize: 11,
                      fontWeight: isWinner
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          Text(
            '★${participant.overallRating.toStringAsFixed(1)}',
            style: TextStyle(color: ratingColor, fontSize: 9),
          ),
        ],
      ),
    );

    if (tag == null) return card;
    // Inside the card's own bounds, not hanging above it. The old `top: -6`
    // overhang collided with the slot above once rows sat close together —
    // visible on an eliminated participant, whose OUT tag overlapped the
    // winner's capsule directly above it.
    return Stack(
      clipBehavior: Clip.none,
      children: [card, Positioned(top: 3, right: 4, child: tag)],
    );
  }
}

/// Small corner tag — icon + short label — used for LIVE / NEXT / OUT so a
/// slot's state is never carried by border color alone.
class _SlotTag extends StatelessWidget {
  const _SlotTag({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 8, color: color),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 7,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Trophy centre (desktop) / final status header (shared with the mobile
// strip's final column) — must always read clearly whether the finalists are
// unknown, partially known, known, live, or complete.
// ---------------------------------------------------------------------------

/// Where the final currently stands, purely derived from data — never
/// changes bracket interpretation, only how it's summarized for display.
enum _FinalStatus { unknown, partial, scheduled, live, complete }

_FinalStatus _finalStatusOf(MatchSnapshot? finalMatch, bool isComplete) {
  if (isComplete) return _FinalStatus.complete;
  if (finalMatch == null) return _FinalStatus.unknown;
  final aKnown =
      finalMatch.participantA.participantId.isNotEmpty &&
      finalMatch.participantA.overallRating != 0.0;
  final bKnown =
      finalMatch.participantB.participantId.isNotEmpty &&
      finalMatch.participantB.overallRating != 0.0;
  if (finalMatch.status == 'simulating') return _FinalStatus.live;
  if (aKnown && bKnown) return _FinalStatus.scheduled;
  if (aKnown || bKnown) return _FinalStatus.partial;
  return _FinalStatus.unknown;
}

class _TrophyCentre extends StatelessWidget {
  final TournamentStateModel state;

  const _TrophyCentre({required this.state});

  MatchSnapshot? get _finalMatch {
    final finalRound = state.rounds.isNotEmpty ? state.rounds.last : null;
    return (finalRound != null && finalRound.matches.isNotEmpty)
        ? finalRound.matches.first
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final isComplete = state.phase == TournamentPhase.complete;
    final finalMatch = _finalMatch;
    final status = _finalStatusOf(finalMatch, isComplete);

    // The centre is one of the reserved "focus" surfaces — layered depth and
    // an angular accent, unlike the ordinary fixture capsules flanking it.
    //
    // Its content adapts to the width it actually gets: the halves are given
    // their minimum first, so at the 700px boundary the centre can be narrow
    // enough that full finalist rows would not fit. `compact` keeps it
    // readable there instead of overflowing.
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxWidth < 150;
        return Center(
          // T5: when the final becomes real — both finalists known, or the
          // tournament decided — the centre's gold focus builds up once.
          // Everything inside is fully rendered throughout; only the glow
          // behind it changes, so no information waits on this.
          child: _FinalGoldBuild(
            active:
                status == _FinalStatus.scheduled ||
                status == _FinalStatus.live ||
                status == _FinalStatus.complete,
            child: FixtureCapsule(
            emphasis: FixtureEmphasis.focus,
            state: switch (status) {
              _FinalStatus.complete => FixtureState.complete,
              _FinalStatus.live => FixtureState.live,
              _FinalStatus.scheduled => FixtureState.finalSet,
              _FinalStatus.partial ||
              _FinalStatus.unknown => FixtureState.unknown,
            },
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 6 : 16,
              vertical: compact ? 10 : 20,
            ),
            semanticLabel: _semanticsFor(status, finalMatch),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _FinalStatusHeader(status: status),
                if (finalMatch != null) ...[
                  SizedBox(height: compact ? 8 : 12),
                  _finalistRow(
                    finalMatch.participantA,
                    finalMatch,
                    compact: compact,
                  ),
                  _VsRule(compact: compact),
                  _finalistRow(
                    finalMatch.participantB,
                    finalMatch,
                    compact: compact,
                  ),
                ],
              ],
            ),
            ),
          ),
        );
      },
    );
  }

  String _semanticsFor(_FinalStatus status, MatchSnapshot? match) {
    final label = switch (status) {
      _FinalStatus.complete => 'Final complete',
      _FinalStatus.live => 'Final live now',
      _FinalStatus.scheduled => 'Final set',
      _FinalStatus.partial => 'Final, one place still open',
      _FinalStatus.unknown => 'Final, finalists not yet known',
    };
    if (match == null) return label;
    String nameOf(ParticipantSnapshot p) =>
        (p.overallRating == 0.0 || p.participantId.isEmpty)
        ? 'to be decided'
        : p.displayName;
    return '$label. ${nameOf(match.participantA)} versus '
        '${nameOf(match.participantB)}';
  }

  /// One finalist. Now a full-width row with a readable name rather than a
  /// 9-character stub — the extra centre width exists precisely for this.
  Widget _finalistRow(
    ParticipantSnapshot p,
    MatchSnapshot match, {
    required bool compact,
  }) {
    final isTBD = p.overallRating == 0.0 || p.participantId.isEmpty;
    final isWinner = match.winnerId == p.participantId;

    if (isTBD) {
      // Genuinely unknown: an intentional placeholder, never a false identity.
      return Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 4 : 10,
          vertical: compact ? 5 : 7,
        ),
        decoration: BoxDecoration(
          color: HETheme.pfSurfaceDeep.withValues(alpha: 0.5),
          border: Border.all(color: HETheme.pfBorder),
          borderRadius: HEShape.sm,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!compact) ...[
              const Icon(
                Icons.help_outline_rounded,
                size: 12,
                color: HETheme.pfTextMuted,
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                compact ? 'TBD' : 'Awaiting finalist',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: HETheme.pfTextMuted,
                  fontSize: compact ? 9 : 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 10,
        vertical: compact ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: isWinner
            ? HETheme.pfGold.withValues(alpha: 0.14)
            : HETheme.pfSurfaceDeep.withValues(alpha: 0.55),
        border: Border.all(
          color: isWinner
              ? HETheme.pfGold.withValues(alpha: 0.75)
              : HETheme.pfBorder,
        ),
        borderRadius: HEShape.sm,
      ),
      child: Row(
        children: [
          if (isWinner && !compact) ...[
            const RankMedallion(rank: 1, size: 16),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              p.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isWinner ? HETheme.pfGold : HETheme.pfTextPrimary,
                fontSize: compact ? 9 : 12,
                fontWeight: isWinner ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          if (p.overallRating > 0 && !compact) ...[
            const SizedBox(width: 6),
            Text(
              p.overallRating.toStringAsFixed(1),
              style: TextStyle(
                color: isWinner
                    ? HETheme.pfGold.withValues(alpha: 0.85)
                    : HETheme.pfTextSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The broadcast "VS" separator between the two finalists.
class _VsRule extends StatelessWidget {
  const _VsRule({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    Widget rule() => Expanded(
      child: Container(
        height: 1,
        color: HETheme.pfBorder.withValues(alpha: 0.7),
      ),
    );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 4 : 6),
      child: Row(
        children: [
          if (!compact) rule(),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 8),
            child: Text(
              'VS',
              style: TextStyle(
                color: HETheme.pfTextSecondary,
                fontSize: compact ? 8 : 10,
                fontWeight: FontWeight.w800,
                letterSpacing: compact ? 0.8 : 1.4,
              ),
            ),
          ),
          if (!compact) rule(),
        ],
      ),
    );
  }
}

/// The trophy icon + "FINAL" label, styled per [_FinalStatus] — shared by the
/// desktop centre column and the mobile strip's final column so the two
/// layouts can never disagree about what the final's status is.
class _FinalStatusHeader extends StatelessWidget {
  const _FinalStatusHeader({required this.status});

  final _FinalStatus status;

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final double iconSize;
    late final List<BoxShadow> glow;
    late final String label;

    switch (status) {
      case _FinalStatus.complete:
        color = HETheme.pfGold;
        iconSize = 52;
        glow = [
          BoxShadow(
            color: HETheme.pfGold.withValues(alpha: 0.5),
            blurRadius: 20,
            spreadRadius: 4,
          ),
        ];
        label = 'FINAL';
        break;
      case _FinalStatus.live:
        color = HETheme.pfDanger;
        iconSize = 44;
        glow = [
          BoxShadow(
            color: HETheme.pfDanger.withValues(alpha: 0.4),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ];
        label = 'FINAL — LIVE';
        break;
      case _FinalStatus.scheduled:
        // Both finalists known, not yet live — "the final is set" is a
        // meaningful moment, so it gets a dim gold read (matching the
        // achievement-adjacent meaning gold carries elsewhere) rather than
        // the flat grey "nothing to see yet" state.
        color = HETheme.pfGold.withValues(alpha: 0.65);
        iconSize = 44;
        glow = [
          BoxShadow(
            color: HETheme.pfGold.withValues(alpha: 0.22),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ];
        label = 'FINAL SET';
        break;
      case _FinalStatus.partial:
        color = Colors.white38;
        iconSize = 40;
        glow = const [];
        label = 'FINAL — 1 SPOT OPEN';
        break;
      case _FinalStatus.unknown:
        color = Colors.white24;
        iconSize = 40;
        glow = const [];
        label = 'FINAL';
        break;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: HEMotion.reduced(context)
              ? Duration.zero
              : const Duration(milliseconds: 600),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: status == _FinalStatus.unknown
                ? Colors.transparent
                : color.withValues(alpha: 0.1),
            boxShadow: glow,
          ),
          child: Icon(Icons.emoji_events, size: iconSize, color: color),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 9,
            letterSpacing: 1.2,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Mobile — one round per horizontally-scrolled, full-height column. A plain
// user-controlled ListView (not a PageView): vertical Tournament Hub
// scrolling must stay unobstructed, and nothing here ever calls `.animateTo`/
// `.jumpTo` — the scroll position is exactly what the user last set it to,
// including across state updates (no auto-scroll-on-refresh).
// ---------------------------------------------------------------------------

class _MobileBracketStrip extends StatelessWidget {
  final TournamentStateModel state;
  final bool isDrawing;
  final List<String> revealPool;

  /// T1: drives the staggered draw reveal, same controller the desktop
  /// layout uses so the two never disagree about whether the draw is
  /// revealing.
  final AnimationController? drawReveal;

  const _MobileBracketStrip({
    required this.state,
    required this.isDrawing,
    required this.revealPool,
    this.drawReveal,
  });

  @override
  Widget build(BuildContext context) {
    final rounds = state.rounds;
    if (rounds.isEmpty) return const SizedBox.shrink();

    final earlyRounds = rounds.sublist(0, rounds.length - 1);
    final finalRound = rounds.last;
    final finalMatch = finalRound.matches.isNotEmpty
        ? finalRound.matches.first
        : null;
    final isComplete = state.phase == TournamentPhase.complete;

    final maxMatches = rounds
        .map((r) => r.matches.length)
        .fold(1, (a, b) => a > b ? a : b);
    final columnHeight =
        24 /* header */ +
        8 +
        maxMatches * kBracketMatchBlockHeight +
        (maxMatches - 1) * 10 +
        // Extra headroom so the final column's status header (trophy icon +
        // label) fits above its single match block without growing the
        // strip's overall height beyond what the other columns already need.
        90;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: columnHeight,
          child: Stack(
            children: [
              ListView(
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  // T1: same staggered settle as the desktop layout, so the
                  // draw reads identically in both.
                  for (int ri = 0; ri < earlyRounds.length; ri++)
                    BracketStaggerIn(
                      controller: drawReveal,
                      order: ri,
                      total: earlyRounds.length + 1,
                      child: _MobileRoundColumn(
                        round: earlyRounds[ri],
                        isDrawing: isDrawing && ri == 0,
                        revealPool: revealPool,
                      ),
                    ),
                  BracketStaggerIn(
                    controller: drawReveal,
                    order: earlyRounds.length,
                    total: earlyRounds.length + 1,
                    child: _MobileFinalColumn(
                      round: finalRound,
                      finalMatch: finalMatch,
                      isComplete: isComplete,
                    ),
                  ),
                ],
              ),
              // Edge fades — the honest, low-effort signal that there's more
              // to scroll to in either direction (a real peek at the next
              // column's edge already does most of the work; this just
              // reinforces it), never a gesture blocker (IgnorePointer).
              const Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 20,
                child: IgnorePointer(child: _EdgeFade(fromLeft: true)),
              ),
              const Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 20,
                child: IgnorePointer(child: _EdgeFade(fromLeft: false)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _StripPips(current: state.currentRound, total: state.totalRounds),
      ],
    );
  }
}

class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.fromLeft});
  final bool fromLeft;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: fromLeft ? Alignment.centerLeft : Alignment.centerRight,
          end: fromLeft ? Alignment.centerRight : Alignment.centerLeft,
          colors: [
            HETheme.pfBgVoid.withValues(alpha: 0.9),
            HETheme.pfBgVoid.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }
}

/// Round-progress dots — the same "which round are we on" language the hub's
/// app bar already uses, restated here as secondary guidance for the strip
/// (not a scroll-position indicator: no scroll listener, no controller,
/// nothing here can trigger an auto-scroll jump).
class _StripPips extends StatelessWidget {
  const _StripPips({required this.current, required this.total});
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final done = i < current;
        return Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? HETheme.pfGold : Colors.white24,
          ),
        );
      }),
    );
  }
}

const double _kMobileColumnWidth = 172;

class _MobileRoundColumn extends StatelessWidget {
  final RoundSnapshot round;
  final bool isDrawing;
  final List<String> revealPool;

  const _MobileRoundColumn({
    required this.round,
    required this.isDrawing,
    required this.revealPool,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kMobileColumnWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ColumnHeader(round.label),
          const SizedBox(height: 8),
          for (final m in round.matches) ...[
            _BracketMatchBlock(
              match: m,
              isDrawing: isDrawing,
              revealPool: revealPool,
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _MobileFinalColumn extends StatelessWidget {
  final RoundSnapshot round;
  final MatchSnapshot? finalMatch;
  final bool isComplete;

  const _MobileFinalColumn({
    required this.round,
    required this.finalMatch,
    required this.isComplete,
  });

  @override
  Widget build(BuildContext context) {
    final status = _finalStatusOf(finalMatch, isComplete);
    return SizedBox(
      width: _kMobileColumnWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ColumnHeader(round.label),
          const SizedBox(height: 4),
          _FinalStatusHeader(status: status),
          const SizedBox(height: 8),
          if (finalMatch != null)
            _BracketMatchBlock(match: finalMatch!)
          else
            Container(
              height: kBracketMatchBlockHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: HETheme.pfSurfaceRaised,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white12),
              ),
              child: const Text(
                'AWAITING FINALISTS',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white24, fontSize: 9),
              ),
            ),
        ],
      ),
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _BracketLinePainter extends CustomPainter {
  final int roundCount;
  final bool isLeft;

  /// T4: which cell's outgoing connector is currently filling, in this half's
  /// own (round, match) coordinates. Null means nothing is advancing and the
  /// painter behaves exactly as it did before Stage 3.
  final ({int round, int match})? advancing;

  /// 0 → 1 along the advancing connector.
  final double progress;

  const _BracketLinePainter({
    required this.roundCount,
    required this.isLeft,
    this.advancing,
    this.progress = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = HETheme.pfSecondaryViolet.withValues(alpha: 0.18)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    if (roundCount < 1) return;

    final colW = size.width / roundCount;

    // Connectors between each round and the next (inner) one.
    for (int r = 0; r < roundCount - 1; r++) {
      // Matches in a half's round r (0 = outermost): 2^(roundCount-1-r).
      final matchesThisRound = _pow2(roundCount - 1 - r);
      final matchesNextRound = matchesThisRound ~/ 2;
      if (matchesNextRound < 1) continue;

      final slotH = size.height / matchesThisRound;
      final nextSlotH = size.height / matchesNextRound;

      for (int m = 0; m < matchesNextRound; m++) {
        final topSrcY = slotH * (m * 2) + slotH / 2;
        final botSrcY = slotH * (m * 2 + 1) + slotH / 2;
        final tgtY = nextSlotH * m + nextSlotH / 2;

        final srcX = isLeft
            ? colW * (r + 1) - 4
            : size.width - colW * (r + 1) + 4;
        final midX = isLeft
            ? colW * (r + 1) + colW / 2
            : size.width - colW * (r + 1) - colW / 2;

        canvas.drawLine(Offset(srcX, topSrcY), Offset(midX, topSrcY), paint);
        canvas.drawLine(Offset(srcX, botSrcY), Offset(midX, botSrcY), paint);
        canvas.drawLine(Offset(midX, topSrcY), Offset(midX, botSrcY), paint);

        final tgtX = isLeft ? colW * (r + 1) : size.width - colW * (r + 1);
        canvas.drawLine(Offset(midX, tgtY), Offset(tgtX, tgtY), paint);
      }
    }

    // Innermost slot (one per side) → trophy edge.
    final slotMidY = size.height / 2;
    final edgeX = isLeft ? size.width : 0.0;
    final preEdgeX = isLeft ? size.width - 8 : 8.0;
    canvas.drawLine(Offset(preEdgeX, slotMidY), Offset(edgeX, slotMidY), paint);

    _paintAdvancing(canvas, size, colW);
  }

  /// T4: draws the winner's path toward the next round on top of the resting
  /// lines, revealed by [progress].
  ///
  /// Only the one connector belonging to [advancing] is drawn here — the rest
  /// of the tree is untouched, so a completed match never triggers a repaint
  /// of the whole bracket.
  void _paintAdvancing(Canvas canvas, Size size, double colW) {
    final cell = advancing;
    if (cell == null || progress <= 0) return;

    final r = cell.round;
    // The outgoing connector runs from this round into the next one.
    if (r >= roundCount - 1) return;

    final matchesThisRound = _pow2(roundCount - 1 - r);
    final matchesNextRound = matchesThisRound ~/ 2;
    if (matchesNextRound < 1) return;

    final slotH = size.height / matchesThisRound;
    final nextSlotH = size.height / matchesNextRound;

    final m = cell.match ~/ 2;
    if (m >= matchesNextRound) return;

    final srcY = slotH * cell.match + slotH / 2;
    final tgtY = nextSlotH * m + nextSlotH / 2;

    final srcX = isLeft ? colW * (r + 1) - 4 : size.width - colW * (r + 1) + 4;
    final midX = isLeft
        ? colW * (r + 1) + colW / 2
        : size.width - colW * (r + 1) - colW / 2;
    final tgtX = isLeft ? colW * (r + 1) : size.width - colW * (r + 1);

    // One continuous path: out from the slot, along to the junction, then in
    // to the next round's slot.
    final path = Path()
      ..moveTo(srcX, srcY)
      ..lineTo(midX, srcY)
      ..lineTo(midX, tgtY)
      ..lineTo(tgtX, tgtY);

    final metrics = path.computeMetrics().toList();
    final totalLength = metrics.fold<double>(0, (a, mm) => a + mm.length);
    var remaining = totalLength * progress.clamp(0.0, 1.0);

    final drawn = Path();
    for (final mm in metrics) {
      if (remaining <= 0) break;
      final take = remaining < mm.length ? remaining : mm.length;
      drawn.addPath(mm.extractPath(0, take), Offset.zero);
      remaining -= take;
    }

    canvas.drawPath(
      drawn,
      Paint()
        ..color = HETheme.pfSuccess.withValues(alpha: 0.85)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  int _pow2(int exp) {
    int result = 1;
    for (int i = 0; i < exp; i++) {
      result *= 2;
    }
    return result;
  }

  @override
  bool shouldRepaint(_BracketLinePainter old) =>
      old.roundCount != roundCount ||
      old.isLeft != isLeft ||
      old.advancing != advancing ||
      old.progress != progress;
}

// ---------------------------------------------------------------------------
// _ShuffleRevealText — the "lucky draw" wheel-spin-then-settle name reveal.
// ---------------------------------------------------------------------------

/// Cycles through [pool] and lands on [finalName] — purely a
/// `TweenAnimationBuilder` (implicit, self-disposing on rebuild/unmount), so
/// there's no `AnimationController`/`Timer` to leak if the page changes mid-
/// draw. The already-decided assignment never changes; this only animates how
/// it's *revealed*.
class _ShuffleRevealText extends StatelessWidget {
  final String finalName;
  final List<String> pool;
  final Duration duration;
  final TextStyle? style;

  const _ShuffleRevealText({
    required this.finalName,
    required this.pool,
    required this.duration,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    if (pool.isEmpty || HEMotion.reduced(context)) {
      return Text(finalName, style: style, overflow: TextOverflow.ellipsis);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOut,
      builder: (context, t, _) {
        if (t >= 0.999) {
          return Text(finalName, style: style, overflow: TextOverflow.ellipsis);
        }
        // Ticks quickly at first and slows near the end, like a wheel
        // settling on its final slot.
        final tick = (t * pool.length * 5).floor();
        return Text(
          pool[tick % pool.length],
          style: style?.copyWith(color: Colors.white38),
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}

/// T5: builds the trophy centre's gold focus up once when the final becomes
/// real, then holds it.
///
/// Deliberately a one-way build, not a loop — a permanently pulsing final
/// would be the second continuous animation on a screen that may already have
/// a live match sweeping, which the motion contract forbids.
///
/// Under reduced motion no controller is constructed and the glow is painted
/// at full strength immediately. The content inside is never faded: only the
/// glow behind it animates, so the finalists are readable from the first
/// frame either way.
class _FinalGoldBuild extends StatefulWidget {
  const _FinalGoldBuild({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_FinalGoldBuild> createState() => _FinalGoldBuildState();
}

class _FinalGoldBuildState extends State<_FinalGoldBuild>
    with SingleTickerProviderStateMixin {
  AnimationController? _build;
  bool _played = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Arriving at a final that is *already* set shows it fully lit rather
    // than animating — the build marks a moment happening now, and replaying
    // it on every mount would make navigating back re-stage old news. Only
    // the false→true transition below animates.
    if (widget.active) _played = true;
  }

  @override
  void didUpdateWidget(_FinalGoldBuild old) {
    super.didUpdateWidget(old);
    // Only a genuine false→true transition starts it; repeated broadcasts
    // while already active change nothing.
    if (!old.active && widget.active) _maybeBuild();
  }

  void _maybeBuild() {
    if (!widget.active || _played) return;
    _played = true;
    if (HEMotion.reduced(context)) return;
    _build = AnimationController(vsync: this, duration: HEMotion.wake)
      ..forward();
  }

  @override
  void dispose() {
    _build?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;

    final controller = _build;
    // No controller → full strength immediately (reduced motion, or settled).
    if (controller == null) return _glow(1.0, widget.child);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) =>
            _glow(HEMotion.easeOut.transform(controller.value), child!),
        child: widget.child,
      ),
    );
  }

  Widget _glow(double t, Widget child) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: HEShape.lg,
      boxShadow: [
        BoxShadow(
          color: HETheme.pfGold.withValues(alpha: 0.40 * t),
          blurRadius: 52 * t,
          spreadRadius: 6 * t,
        ),
      ],
    ),
    child: child,
  );
}

/// T1/T2: fades and lifts one bracket element into place as part of a single
/// shared entrance, staggered by [order].
///
/// A null [controller] means there is nothing to animate — reduced motion, or
/// an entrance that has already played — and the child is returned untouched
/// at its final state. Identities are never hidden: this only affects opacity
/// and a small offset, and the whole sequence fits inside one `entrance`
/// token, so no capsule is unreadable for long.
class BracketStaggerIn extends StatelessWidget {
  const BracketStaggerIn({
    super.key,
    required this.controller,
    required this.order,
    required this.total,
    required this.child,
  });

  final AnimationController? controller;
  final int order;
  final int total;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null) return child;

    final span = total <= 1 ? 1.0 : 1.0 / (total + 1);
    final begin = (order * span).clamp(0.0, 0.6);
    final animation = CurvedAnimation(
      parent: c,
      curve: Interval(begin, 1.0, curve: HEMotion.easeOut),
    );

    return RepaintBoundary(
      child: FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.10),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
    );
  }
}
