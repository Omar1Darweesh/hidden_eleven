import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hidden_eleven/app/he_motion.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/app/routes.dart';
import 'package:hidden_eleven/features/game/game_provider.dart';
import 'package:hidden_eleven/features/lobby/room_provider.dart';
import 'package:hidden_eleven/shared/widgets/context_help_button.dart';
import 'package:hidden_eleven/shared/widgets/help_dialog.dart';
import 'package:hidden_eleven/shared/widgets/event_atmosphere_background.dart';
import 'package:hidden_eleven/shared/widgets/hex_progress_ring.dart';
import '../models/tournament_models.dart';
import '../providers/tournament_provider.dart';
import '../widgets/tournament_widgets.dart';

/// The readable measure the tournament event is centred inside.
///
/// Wide enough for a 4-team bracket to breathe either side of an enlarged
/// Trophy Centre, narrow enough that a fixture capsule stays a capsule
/// instead of inflating into a full-width bar on a 1920px display. Below
/// this width the layout simply fills what it has, so phones and laptops are
/// unaffected.
const double kHubMaxWidth = 1180;

/// Tournament page help — bracket/rounds, ready check, live match details,
/// penalties, and the award tie rules. Kept next to the screen it describes.
const _tournamentHelpSections = <HelpSection>[
  HelpSection('BRACKET & ROUNDS', [
    HelpEntry(
      'How it works',
      'Teams are drawn into a knockout bracket. Win your match to advance; '
          'lose and you\'re out. The bracket at the top always shows the '
          'live state of every round.',
    ),
    HelpEntry(
      'Rounds do not auto-advance',
      'A finished round stays visible so you can review it. The next round '
          'only begins once every manager presses Ready — never automatically.',
    ),
  ]),
  HelpSection('READY CHECK', [
    HelpEntry(
      'What it means',
      'Before a round\'s matches simulate, every real manager in that round '
          'must confirm Ready. Managers who don\'t respond in time are '
          'auto-readied so the tournament can continue.',
    ),
  ]),
  HelpSection('LIVE MATCH DETAILS', [
    HelpEntry(
      'Expand a card',
      'Tap a match card to open its live event timeline in place — no '
          'separate screen. Goals, cards, and big chances appear as they '
          'happen, split by team side.',
    ),
    HelpEntry(
      'Penalties',
      'A match level after regulation goes to a real penalty shootout. The '
          'result reads like real football, e.g. "1–1 (4–3 pens)" — a '
          'sent-off player can never step up to take a penalty.',
    ),
  ]),
  HelpSection('TOURNAMENT AWARDS', [
    HelpEntry(
      'How leaders are decided',
      'Top Scorer and Top Assists rank by goals/assists. Top Contributions '
          'ranks by goals + assists combined. Best Rating ranks by real '
          'tournament match ratings, not pre-tournament squad rating.',
    ),
    HelpEntry(
      'Tie rules',
      'A tie is broken by whichever player logged fewer minutes played '
          '(Best Rating has no minutes tiebreak). If still tied, the award '
          'is shared — every tied winner gets an equal, rounded-up share of '
          'the bonus points (e.g. 15 split 2 ways → 8 each).',
    ),
  ]),
];

/// The single, complete tournament experience — a broadcast "control room":
///
///   header ▸ phase/draw/ready banner ▸ bracket ▸ match cards (in-place
///   accordions) ▸ live leaderboard ▸ points ▸ result CTA.
///
/// Every player renders from the same server-pushed [TournamentStateModel]
/// (phase, shared `bracketRevealAt` / `readyDeadlineAt` deadlines,
/// `readyPlayerIds`, bracket, awards), so the draw, the ready state, the
/// countdown, and the standings are identical for everyone. There is no
/// separate live-broadcast route and no route-based match details.
class TournamentHubScreen extends ConsumerStatefulWidget {
  const TournamentHubScreen({super.key});

  @override
  ConsumerState<TournamentHubScreen> createState() =>
      _TournamentHubScreenState();
}

class _TournamentHubScreenState extends ConsumerState<TournamentHubScreen> {
  // Drives the whole-bracket fade-in on entry (the visible "draw" reveal).
  bool _bracketRevealed = false;

  // Instant local feedback for the READY press, keyed by round so it resets
  // automatically when the next round's ready check begins. The authoritative
  // ready state still comes from the shared `readyPlayerIds`.
  int? _readyPressedForRound;

  // Previous rounds stay on the page (never auto-hidden) but collapse by
  // default so the page doesn't grow unbounded — one tap re-opens them.
  final Set<int> _expandedPreviousRounds = {};

  // Team journey cards default collapsed; one tap per team reveals its path.
  final Set<String> _expandedJourneyTeams = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _bracketRevealed = true);
    });
  }

  String get _roomCode {
    return GoRouterState.of(context).pathParameters['roomCode'] ?? '';
  }

  void _sendReady(int round) {
    setState(() => _readyPressedForRound = round);
    ref.read(roomProvider.notifier).sendTournamentReady();
  }

  /// Leaving is explicit and confirmed — never a stray back gesture.
  ///
  /// Uses the same exit path the game screen already uses, so the server is
  /// told the player is going rather than being left with a client that has
  /// silently navigated away from an event it is still enrolled in.
  Future<void> _confirmLeaveTournament() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HETheme.pfSurfaceRaised,
        title: const Text('Leave tournament?'),
        content: const Text(
          'You will exit to the home screen. The tournament continues '
          'without you and you will not be able to rejoin it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: HETheme.pfDanger),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (leave != true || !mounted) return;
    ref.read(roomProvider.notifier).exitGameToHome();
    ref.read(gameProvider.notifier).reset();
    if (mounted) context.goNamed(Routes.home);
  }

  RoundSnapshot _currentRound(TournamentStateModel state) {
    return state.rounds.firstWhere(
      (r) => r.roundNumber == state.currentRound,
      orElse: () => state.rounds.last,
    );
  }

  List<MatchSnapshot> _currentRoundMatches(TournamentStateModel state) {
    return _currentRound(state).matches;
  }

  /// Real participant ids in the current round (used for the shared ready tally).
  List<String> _currentRoundRealIds(TournamentStateModel state) {
    final out = <String>[];
    for (final m in _currentRoundMatches(state)) {
      for (final p in [m.participantA, m.participantB]) {
        if (p.kind == TournamentParticipantKind.real &&
            p.participantId.isNotEmpty) {
          out.add(p.participantId);
        }
      }
    }
    return out;
  }

  /// Rounds already played (or in progress) before the current one, most
  /// recent first — these stay on the page so their match details remain
  /// reviewable instead of disappearing the moment the round counter advances.
  List<RoundSnapshot> _previousRounds(TournamentStateModel state) {
    return state.rounds
        .where((r) => r.roundNumber < state.currentRound)
        .toList()
        .reversed
        .toList();
  }

  String _participantName(TournamentStateModel state, String id) {
    for (final round in state.rounds) {
      for (final m in round.matches) {
        for (final p in [m.participantA, m.participantB]) {
          if (p.participantId == id) return p.displayName;
        }
      }
    }
    return id;
  }

  /// True while the just-finished round should stay the primary visible
  /// context — i.e. the next round has only just entered ready_check and
  /// hasn't produced anything worth looking at yet.
  bool _promoteRecentPrevious(TournamentStateModel state) {
    return state.phase == TournamentPhase.readyCheck &&
        _previousRounds(state).isNotEmpty;
  }

  Widget _buildPreviousSection(
    TournamentStateModel state,
    RoundSnapshot prev, {
    bool highlight = false,
  }) {
    return _PreviousRoundSection(
      round: prev,
      expanded: _expandedPreviousRounds.contains(prev.roundNumber),
      highlight: highlight,
      onToggle: () => setState(() {
        if (!_expandedPreviousRounds.remove(prev.roundNumber)) {
          _expandedPreviousRounds.add(prev.roundNumber);
        }
      }),
      matchBuilder: (match) {
        final liveEvents =
            ref.watch(liveMatchEventsProvider)[match.matchId] ?? [];
        final result = ref.watch(completedMatchResultsProvider)[match.matchId];
        final myId = ref.watch(myParticipantIdProvider);
        return MatchCardWidget(
          match: match,
          myParticipantId: myId,
          readyParticipantIds: state.readyPlayerIds,
          liveEvents: liveEvents,
          completedResult: result,
          roundLabel: prev.label,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tournamentStateProvider);

    // The instant a round ends and the round counter advances, keep that
    // just-finished round open rather than letting it collapse into history
    // at the same moment the next round's ready-check UI appears.
    ref.listen<TournamentStateModel?>(tournamentStateProvider, (prev, next) {
      if (prev != null &&
          next != null &&
          next.currentRound > prev.currentRound) {
        setState(() => _expandedPreviousRounds.add(prev.currentRound));
      }
    });

    // A rejected tournament_ready (e.g. the round already moved on — race
    // between this tap and a game_state/tournament_state transition — or
    // this player's local view of "my round" was momentarily stale) had no
    // feedback at all: _readyPressedForRound is set optimistically the
    // instant Ready is tapped and only ever cleared when state.currentRound
    // advances, so a genuinely rejected press left the button permanently
    // hidden behind "You're ready — waiting for the other managers" even
    // though the server never recorded it — a real broken-loading-loop, not
    // just a missing toast. Resetting the flag here lets the real button
    // (driven by server-truth readyPlayerIds) reappear immediately.
    ref.listen(serverErrorProvider, (_, next) {
      next.whenData((err) {
        if (!mounted) return;
        if (err.code != 'TOURNAMENT_NOT_IN_READY_CHECK' &&
            err.code != 'TOURNAMENT_NOT_YOUR_ROUND') {
          return;
        }
        if (_readyPressedForRound != null) {
          setState(() => _readyPressedForRound = null);
        }
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Ready check has already moved on.')),
          );
      });
    });

    // Auto-ready toasts (AI ready / opponent timed out).
    ref.listen(tournamentAutoReadyProvider, (_, next) {
      next.whenData((event) {
        if (!mounted) return;
        String name = event.participantId;
        if (state != null) {
          for (final round in state.rounds) {
            for (final match in round.matches) {
              for (final p in [match.participantA, match.participantB]) {
                if (p.participantId == event.participantId) {
                  name = p.displayName;
                }
              }
            }
          }
        }
        final label = event.reason == 'timeout'
            ? 'was auto-readied (timeout)'
            : 'is ready (AI)';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⏰ $name $label'),
            duration: const Duration(seconds: 3),
          ),
        );
      });
    });

    if (state == null) {
      return const Scaffold(
        backgroundColor: HETheme.pfBgVoid,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final round = _currentRound(state);
    final reduceMotion = HEMotion.reduced(context);
    final isNarrow =
        MediaQuery.sizeOf(context).width < HETheme.breakpointMobile;

    return Scaffold(
      backgroundColor: HETheme.pfBgVoid,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        // No back arrow. "Back" out of a live tournament has no meaning — the
        // server keeps you in the event either way, so popping the route just
        // desyncs the client from a tournament it is still part of. Leaving is
        // an explicit, server-acknowledged action instead, exactly as the game
        // and lobby screens already treat it.
        automaticallyImplyLeading: false,
        leading: const SizedBox.shrink(),
        titleSpacing: 16,
        // The event identity, round and pips now live in EventHeader, in the
        // body, where they can carry real hierarchy. Keeping them here too
        // would say the same thing twice — so the bar keeps only navigation
        // and help.
        title: const Icon(
          Icons.emoji_events,
          color: HETheme.pfGold,
          size: 24,
        ),
        actions: [
          const ContextHelpButton(
            contextKey: 'tournament',
            title: 'Tournament',
            fallbackSections: _tournamentHelpSections,
          ),
          // The one way out — deliberate, confirmed, and server-acknowledged,
          // replacing the implicit back arrow this screen used to inherit.
          IconButton(
            tooltip: 'Leave tournament',
            icon: const Icon(
              Icons.exit_to_app_rounded,
              size: 20,
              color: HETheme.pfTextSecondary,
            ),
            onPressed: _confirmLeaveTournament,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          // Original Night Tactics atmosphere, replacing the flat three-stop
          // gradient this screen used to sit on. Static and non-interactive;
          // the gold radial is withheld until the final is actually set (see
          // `goldFocus` below), so gold stays an achievement signal rather
          // than page decoration.
          Positioned.fill(
            child: EventAtmosphereBackground(
              variant: EventAtmosphereVariant.tournament,
              goldFocus: _finalIsInFocus(state),
              goldAlignment: const Alignment(0, -0.15),
            ),
          ),
          SingleChildScrollView(
          // The whole event is centred inside a readable measure rather than
          // stretching to the viewport. Without this, a 1920px screen gave
          // each bracket half ~830px, inflating a fixture capsule into a
          // near-empty bar with the name at one end and the rating at the
          // other — and leaving the Trophy Centre, capped at 240px, as the
          // *smallest* element on the page. Content that is meant to lead
          // has to be able to out-weigh what surrounds it.
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kHubMaxWidth),
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Broadcast event header + journey rail ────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EventHeader(
                      roundLabel: round.label,
                      status: _phaseStatusLabel(state),
                      statusColor: _phaseStatusColor(state),
                      statusIcon: _phaseStatusIcon(state),
                      compact: isNarrow,
                      pips: _RoundPips(
                        current: state.currentRound,
                        total: state.totalRounds,
                      ),
                    ),
                    const SizedBox(height: 10),
                    StageRail(
                      stages: _stagesFor(state),
                      currentIndex: _currentStageIndex(state),
                      compact: isNarrow,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── Phase / draw / ready banner ──────────────────────────────
              AnimatedSwitcher(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 350),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: KeyedSubtree(
                  key: ValueKey(state.phase),
                  child: _buildPhaseBanner(state),
                ),
              ),

              // ── Bracket (the draw result) — fades in on entry ────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AnimatedOpacity(
                  opacity: _bracketRevealed ? 1.0 : 0.0,
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 600),
                  child: TournamentBracketWidget(state: state),
                ),
              ),

              // While the next round is only waiting on ready-check (nothing
              // live or complete there yet), keep the just-finished round as
              // the primary visible context instead of letting the
              // ready-check UI take over the page immediately.
              if (_promoteRecentPrevious(state))
                _buildPreviousSection(
                  state,
                  _previousRounds(state).first,
                  highlight: true,
                ),

              _sectionDivider(round.label.toUpperCase()),

              // ── Current round: match cards with in-place expandable details ──
              //
              // T2: the round's cards ease in together as one broadcast-style
              // entrance, keyed to the round number so it plays once per round
              // rather than on every `game_state` broadcast within a round.
              ..._currentRoundMatches(state).indexed.map((entry) {
                final (cardIndex, match) = entry;
                final liveEvents =
                    ref.watch(liveMatchEventsProvider)[match.matchId] ?? [];
                final result = ref.watch(
                  completedMatchResultsProvider,
                )[match.matchId];
                final myId = ref.watch(myParticipantIdProvider);
                return _RoundCardEntrance(
                  // A new round produces a new key, which is what makes the
                  // entrance play exactly once per round.
                  key: ValueKey('round-${state.currentRound}-$cardIndex'),
                  order: cardIndex,
                  child: MatchCardWidget(
                    match: match,
                    myParticipantId: myId,
                    readyParticipantIds: state.readyPlayerIds,
                    liveEvents: liveEvents,
                    completedResult: result,
                    roundLabel: round.label,
                    onReady: () => _sendReady(state.currentRound),
                  ),
                );
              }),

              // ── Previous rounds — never auto-hidden, one tap to review ──────
              for (final prev in _previousRounds(state))
                if (!_promoteRecentPrevious(state) ||
                    prev.roundNumber !=
                        _previousRounds(state).first.roundNumber)
                  _buildPreviousSection(state, prev),

              const SizedBox(height: 8),

              // ── Team journey — each team's round-by-round path ───────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: TeamJourneySection(
                  state: state,
                  liveEvents: ref.watch(liveMatchEventsProvider),
                  expandedTeamIds: _expandedJourneyTeams,
                  onToggle: (id) => setState(() {
                    if (!_expandedJourneyTeams.remove(id)) {
                      _expandedJourneyTeams.add(id);
                    }
                  }),
                ),
              ),

              const SizedBox(height: 8),

              // ── Live leaderboard + points ────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TournamentLeaderboard(
                  state: state,
                  liveEvents: ref.watch(liveMatchEventsProvider),
                  results: ref.watch(completedMatchResultsProvider),
                  awards: state.awards,
                ),
              ),

              const SizedBox(height: 28),
            ],
              ),
            ),
          ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // Event header / stage rail helpers.
  //
  // All presentation-only: they read the same TournamentStateModel the screen
  // already had and translate it into labels. None of them advances,
  // computes or infers tournament progress.
  // ───────────────────────────────────────────────────────────────────────

  /// Whether the reserved gold atmosphere should be lit — only once the final
  /// is genuinely the story (final round reached, or the tournament decided).
  bool _finalIsInFocus(TournamentStateModel state) =>
      state.phase == TournamentPhase.complete ||
      state.currentRound >= state.totalRounds;

  // Exhaustive over TournamentPhase on purpose: if a phase is ever added,
  // this fails to compile rather than silently showing no status.
  String _phaseStatusLabel(TournamentStateModel state) =>
      switch (state.phase) {
        TournamentPhase.bracketReveal => 'The draw is set',
        TournamentPhase.readyCheck => 'Ready check',
        TournamentPhase.simulating => 'Round live',
        TournamentPhase.roundResult => 'Round complete',
        TournamentPhase.complete => 'Tournament complete',
      };

  Color _phaseStatusColor(TournamentStateModel state) => switch (state.phase) {
    TournamentPhase.simulating => HETheme.pfDanger,
    TournamentPhase.readyCheck => HETheme.pfWarning,
    TournamentPhase.roundResult => HETheme.pfSuccess,
    TournamentPhase.complete => HETheme.pfGold,
    _ => HETheme.pfAccentViolet,
  };

  IconData _phaseStatusIcon(TournamentStateModel state) =>
      switch (state.phase) {
        TournamentPhase.simulating => Icons.podcasts_rounded,
        TournamentPhase.readyCheck => Icons.how_to_reg_rounded,
        TournamentPhase.roundResult => Icons.check_circle_rounded,
        TournamentPhase.complete => Icons.emoji_events_rounded,
        _ => Icons.account_tree_rounded,
      };

  /// The journey as named stops: the draw, one stop per round (using the
  /// round's own label so nothing is invented), then the champion.
  List<TournamentStage> _stagesFor(TournamentStateModel state) {
    final complete = state.phase == TournamentPhase.complete;
    return [
      const TournamentStage(label: 'Draw', done: true),
      for (final r in state.rounds)
        TournamentStage(
          label: r.label,
          done: complete || r.roundNumber < state.currentRound,
        ),
      TournamentStage(label: 'Champion', done: complete),
    ];
  }

  /// Index of the stage the tournament is actually in. Returns -1 rather than
  /// guessing when the current round isn't among the known rounds.
  int _currentStageIndex(TournamentStateModel state) {
    if (state.phase == TournamentPhase.complete) {
      return _stagesFor(state).length - 1;
    }
    final i = state.rounds.indexWhere(
      (r) => r.roundNumber == state.currentRound,
    );
    // +1 for the leading "Draw" stage.
    return i < 0 ? -1 : i + 1;
  }

  // ───────────────────────────────────────────────────────────────────────
  // Phase banner — the broadcast "state machine" surface.
  // ───────────────────────────────────────────────────────────────────────

  Widget _buildPhaseBanner(TournamentStateModel state) {
    final realIds = _currentRoundRealIds(state);
    final readyCount = realIds.where(state.readyPlayerIds.contains).length;
    final myId = ref.watch(myParticipantIdProvider);
    final amInRound = myId != null && realIds.contains(myId);
    final amReady =
        (myId != null && state.readyPlayerIds.contains(myId)) ||
        _readyPressedForRound == state.currentRound;

    late final Color accent;
    late final IconData icon;
    late final String title;
    late final String subtitle;
    int? countdownDeadline;
    String countdownLabel = '';

    switch (state.phase) {
      case TournamentPhase.bracketReveal:
        accent = HETheme.pfGold;
        icon = Icons.casino;
        title = 'THE DRAW';
        subtitle = 'Matchups locked in — the bracket is set';
        countdownDeadline = state.bracketRevealAt;
        countdownLabel = 'Kick-off in';
        break;
      case TournamentPhase.readyCheck:
        accent = HETheme.pfWarning;
        icon = Icons.how_to_reg;
        title = 'READY CHECK';
        subtitle = '$readyCount of ${realIds.length} managers ready';
        countdownDeadline = state.readyDeadlineAt;
        countdownLabel = 'Auto-ready in';
        break;
      case TournamentPhase.simulating:
        accent = HETheme.pfDanger;
        icon = Icons.stadium;
        title = 'ROUND LIVE';
        subtitle = 'Matches in progress — expand a card to follow the action';
        break;
      case TournamentPhase.roundResult:
        accent = HETheme.pfAccentViolet;
        icon = Icons.done_all;
        title = 'ROUND COMPLETE';
        subtitle =
            "Results are in — review them below. The next round won't "
            'begin until every manager presses ready.';
        break;
      case TournamentPhase.complete:
        accent = HETheme.pfGold;
        icon = Icons.emoji_events;
        title = 'TOURNAMENT COMPLETE';
        subtitle = 'Champion: ${state.awards?.champion.displayName ?? '—'}';
        break;
    }

    Widget? body;
    if (state.phase == TournamentPhase.readyCheck) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              HexProgressRing(
                current: readyCount,
                total: realIds.length,
                color: accent,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _ReadyChipsRow(
                  names: [for (final id in realIds) _participantName(state, id)],
                  readyFlags: [
                    for (final id in realIds) state.readyPlayerIds.contains(id),
                  ],
                  accent: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildReadyControl(state, accent, amInRound, amReady),
        ],
      );
    } else if (state.phase == TournamentPhase.complete) {
      body = SizedBox(
        height: 50,
        child: ElevatedButton.icon(
          onPressed: () => context.go('/result/$_roomCode'),
          icon: const Icon(Icons.leaderboard, size: 20),
          label: const Text(
            'GO TO RESULT PAGE',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: HEShape.sm),
          ),
        ),
      );
    }

    return EventPhaseBanner(
      accent: accent,
      icon: icon,
      title: title,
      subtitle: subtitle,
      titleTrailing: state.phase == TournamentPhase.readyCheck
          ? const InlineHelp(
              'Every real manager in this round must confirm ready before '
              'matches simulate — never automatic.',
            )
          : null,
      trailing: countdownDeadline != null
          ? _CountdownChip(
              deadline: countdownDeadline,
              label: countdownLabel,
              accent: accent,
            )
          : null,
      body: body,
    );
  }

  Widget _buildReadyControl(
    TournamentStateModel state,
    Color accent,
    bool amInRound,
    bool amReady,
  ) {
    if (!amInRound) {
      return const Row(
        children: [
          Icon(Icons.visibility, size: 16, color: Colors.white38),
          SizedBox(width: 8),
          Text(
            'Spectating this round',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ],
      );
    }
    if (amReady) {
      return Row(
        children: [
          Icon(Icons.check_circle, size: 18, color: accent),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              "You're ready — waiting for the other managers",
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      );
    }
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: () => _sendReady(state.currentRound),
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: HEShape.sm),
        ),
        child: const Text(
          "I'M READY",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _sectionDivider(String label) => Container(
    margin: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
    child: Row(
      children: [
        const Expanded(child: Divider(color: Colors.white12)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 11,
              letterSpacing: 2,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const Expanded(child: Divider(color: Colors.white12)),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// _ReadyChipsRow — per-player ready state, spelled out by name.
// ---------------------------------------------------------------------------

class _ReadyChipsRow extends StatelessWidget {
  final List<String> names;
  final List<bool> readyFlags;
  final Color accent;

  const _ReadyChipsRow({
    required this.names,
    required this.readyFlags,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (int i = 0; i < names.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: readyFlags[i]
                  ? accent.withValues(alpha: 0.14)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: HEShape.pill,
              border: Border.all(
                color: readyFlags[i]
                    ? accent.withValues(alpha: 0.6)
                    : Colors.white24,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  readyFlags[i] ? Icons.check_circle : Icons.hourglass_bottom,
                  size: 13,
                  color: readyFlags[i] ? accent : Colors.white38,
                ),
                const SizedBox(width: 5),
                Text(
                  names[i],
                  style: TextStyle(
                    color: readyFlags[i] ? Colors.white : Colors.white54,
                    fontSize: 12,
                    fontWeight: readyFlags[i]
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _PreviousRoundSection — a collapsible section keeping a finished round's
// match cards reachable instead of letting them vanish when the round
// counter advances. Purely `AnimatedSize` + a bool — no controllers/timers.
// ---------------------------------------------------------------------------

class _PreviousRoundSection extends StatelessWidget {
  final RoundSnapshot round;
  final bool expanded;
  final bool highlight;
  final VoidCallback onToggle;
  final Widget Function(MatchSnapshot match) matchBuilder;

  const _PreviousRoundSection({
    required this.round,
    required this.expanded,
    required this.onToggle,
    required this.matchBuilder,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    // A promoted (just-finished) round reads as the primary section — a
    // brighter border/icon and "JUST FINISHED" label instead of the muted
    // "history" treatment older rounds get.
    final accent = highlight ? HETheme.pfAccentViolet : Colors.white38;
    final headerLabel = highlight
        ? '${round.label.toUpperCase()} — JUST FINISHED'
        : '${round.label.toUpperCase()} — RESULTS';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: HEShape.sm,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: highlight
                    ? accent.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.03),
                borderRadius: HEShape.sm,
                border: Border.all(
                  color: highlight
                      ? accent.withValues(alpha: 0.5)
                      : Colors.white10,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    highlight ? Icons.check_circle : Icons.history,
                    size: 15,
                    color: accent,
                  ),
                  const SizedBox(width: 8),
                  // Flexible: a longer round label (e.g. "QUARTERFINALS —
                  // JUST FINISHED") must shrink instead of pushing the
                  // trailing expand/collapse icon off narrow screens — a
                  // Spacer only expands, it never shrinks a fixed sibling.
                  Flexible(
                    child: Text(
                      headerLabel,
                      style: TextStyle(
                        color: highlight ? Colors.white : Colors.white54,
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: accent,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: HEMotion.reduced(context)
                ? Duration.zero
                : const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: round.matches.map(matchBuilder).toList(),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small header widgets.
// ---------------------------------------------------------------------------

/// Round progress dots in the app bar (e.g. ●●○ for round 2 of 3).
class _RoundPips extends StatelessWidget {
  final int current;
  final int total;
  const _RoundPips({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (i) {
        final done = i < current;
        return Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? HETheme.pfGold : Colors.white24,
          ),
        );
      }),
    );
  }
}

/// A pill wrapping the shared [CountdownTimerWidget] so the same server
/// deadline reads identically on every client.
class _CountdownChip extends StatelessWidget {
  final int? deadline;
  final String label;
  final Color accent;
  const _CountdownChip({
    required this.deadline,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: HEShape.sm,
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: CountdownTimerWidget(deadlineEpochMs: deadline, label: label),
    );
  }
}

/// T2: eases one of the current round's match cards into place.
///
/// Plays once per round: the widget is keyed by round number, so a new round
/// builds a new state and animates, while every `game_state` broadcast *within*
/// a round (a goal, a ready flag, a score change) rebuilds the same state and
/// leaves the card settled.
///
/// Under reduced motion no controller is constructed and the card is returned
/// untouched at full opacity. The card stays fully interactive throughout
/// either way — neither transition absorbs hit tests, so the ready button and
/// the expand toggle work from the first frame.
class _RoundCardEntrance extends StatefulWidget {
  const _RoundCardEntrance({
    super.key,
    required this.order,
    required this.child,
  });

  final int order;
  final Widget child;

  @override
  State<_RoundCardEntrance> createState() => _RoundCardEntranceState();
}

class _RoundCardEntranceState extends State<_RoundCardEntrance>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ctrl != null || HEMotion.reduced(context)) return;
    _ctrl = AnimationController(vsync: this, duration: HEMotion.land)
      ..forward();
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctrl;
    if (c == null) return widget.child;

    // Cards start within the first 40% of the window, so even the last one is
    // fully readable well inside a single `land`.
    final begin = (widget.order * 0.12).clamp(0.0, 0.4);
    final animation = CurvedAnimation(
      parent: c,
      curve: Interval(begin, 1.0, curve: HEMotion.easeOut),
    );

    return RepaintBoundary(
      child: FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(animation),
          child: widget.child,
        ),
      ),
    );
  }
}
