import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/shared/widgets/context_help_button.dart';
import 'package:hidden_eleven/shared/widgets/help_dialog.dart';
import '../models/tournament_models.dart';
import 'match_phase.dart';
import 'tournament_event_feed_item.dart';

/// Live match details help — the sided timeline layout, event types,
/// shootout display, and the sent-off-player rule.
const _matchDetailsHelpSections = <HelpSection>[
  HelpSection('EVENT TIMELINE', [
    HelpEntry(
      'Left side vs right side',
      'Events for the team named on the left render on the left; the '
          'other team\'s events render on the right. A shared minute rail '
          'runs down the centre, so you can follow both teams at a glance.',
    ),
    HelpEntry(
      'Event types',
      '⚽ Goal (with assist if any) · 🟨 Yellow Card · 🟥 Red Card · '
          '💨 Big Chance Missed — each shows the minute and player.',
    ),
  ]),
  HelpSection('PENALTIES', [
    HelpEntry(
      'Shootout display',
      'A match level after 90 minutes goes to a real shootout — individual '
          'kicks appear in the same timeline (labelled "P1", "P2", …), and '
          'the final result reads like "1–1 (4–3 pens)".',
    ),
  ]),
  HelpSection('PLAYER STATE', [
    HelpEntry(
      'Sent-off players',
      'Once a player receives a red card, they cannot score, assist, miss '
          'a chance, pick up another card, or take a penalty later in that '
          'same match — the event log always stays realistic.',
    ),
  ]),
];

/// Broadcast-style match details rendered INSIDE the match card (accordion),
/// replacing the old separate live-broadcast route.
///
/// Deliberately a StatelessWidget: no AnimationControllers, timers, scroll
/// controllers, or imperative list logic live here, so expanding / collapsing
/// (or toggling cards rapidly) can never leave a dangling callback or freeze
/// the page. The events render as a plain Column inside the hub's existing
/// scroll view — no nested scrollable, no AnimatedList.
class MatchDetailsPanel extends StatelessWidget {
  final MatchSnapshot match;
  final List<LiveMatchEvent> liveEvents;
  final TournamentMatchResult? completedResult;

  const MatchDetailsPanel({
    super.key,
    required this.match,
    required this.liveEvents,
    this.completedResult,
  });

  @override
  Widget build(BuildContext context) {
    final completed = completedResult;
    final isLive = completed == null && match.status == 'simulating';
    final lastEvent = liveEvents.isNotEmpty ? liveEvents.last : null;
    final inShootoutNow =
        lastEvent != null && isPenaltyShootoutEvent(lastEvent);
    final minute = (lastEvent != null && !inShootoutNow) ? lastEvent.minute : 0;
    final wasDecidedByPenalties = completed?.wasDecidedByPenalties ?? false;
    final stats = completed?.stats;
    // Same source of truth the compact match-card header uses — the two can
    // never disagree about what phase the match is actually in.
    final phase = computeMatchPhase(
      match: match,
      liveEvents: liveEvents,
      completedResult: completed,
    );

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: HETheme.pfSurfaceDeep,
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Live minute progress (regulation time only) ───────────────────
          if (isLive && liveEvents.isNotEmpty && !inShootoutNow) ...[
            Row(
              children: [
                Text(
                  phase.label,
                  style: const TextStyle(
                    color: HETheme.pfAccentViolet,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      // Progress within the current half (0–45'), not the
                      // whole 90' — a 2nd-half bar starting at 46' shouldn't
                      // render as "already 51% through the match".
                      value: ((minute > 45 ? minute - 45 : minute) / 45.0)
                          .clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: Colors.white10,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        HETheme.pfAccentViolet,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  "$minute'",
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // ── Live shootout-in-progress banner ───────────────────────────────
          if (isLive && inShootoutNow) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: HETheme.pfGold.withValues(alpha: 0.08),
                borderRadius: HEShape.sm,
              ),
              child: Center(
                child: Text(
                  // Includes the live tally (phase.minuteText, e.g. "3–2") so
                  // this banner visibly updates with every kick instead of
                  // reading as a static "LIVE" for the whole shootout.
                  '🥅  PENALTY SHOOTOUT — LIVE'
                  '${phase.minuteText != null ? ' · ${phase.minuteText}' : ''}',
                  style: const TextStyle(
                    color: HETheme.pfGold,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],

          // ── Team-side header — establishes left = participantA, right =
          // participantB BEFORE the reader starts scanning events below.
          if (liveEvents.isNotEmpty || completed != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      match.participantA.displayName.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 9,
                        letterSpacing: 1,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 46,
                    child: Center(
                      child: ContextHelpButton(
                        contextKey: 'match_details',
                        title: 'Match Details',
                        fallbackSections: _matchDetailsHelpSections,
                        size: 14,
                        compact: true,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      match.participantB.displayName.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 9,
                        letterSpacing: 1,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Divider(color: Colors.white10, height: 1),
            ),
          ],

          // ── Event timeline (sided by team — see TournamentEventFeedItem) ──
          if (liveEvents.isEmpty && completed == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text(
                  'Waiting for kick-off…',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            )
          else
            ...liveEvents.map(
              (e) => TournamentEventFeedItem(
                event: e,
                isTeamA:
                    e.teamParticipantId == match.participantA.participantId,
              ),
            ),

          // ── Completed: penalty result + stats ─────────────────────────────
          if (completed != null) ...[
            const SizedBox(height: 10),
            if (wasDecidedByPenalties)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: HETheme.pfGold.withValues(alpha: 0.10),
                  borderRadius: HEShape.sm,
                  border: Border.all(
                    color: HETheme.pfGold.withValues(alpha: 0.6),
                  ),
                ),
                child: Column(
                  children: [
                    const Text(
                      'DECIDED ON PENALTIES',
                      style: TextStyle(
                        color: HETheme.pfGold,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${completed.penaltyScoreA} – ${completed.penaltyScoreB}',
                      style: const TextStyle(
                        color: HETheme.pfGold,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
              ),
            if (stats != null) ...[
              _DualStatBar(
                label: 'POSSESSION',
                leftVal: stats.possessionA,
                rightVal: 100 - stats.possessionA,
                leftSuffix: '%',
                rightSuffix: '%',
              ),
              const SizedBox(height: 10),
              _DualStatBar(
                label: 'SHOTS',
                leftVal: stats.shotsA,
                rightVal: stats.shotsB,
              ),
              const SizedBox(height: 10),
              _DualStatBar(
                label: 'ON TARGET',
                leftVal: stats.shotsOnTargetA,
                rightVal: stats.shotsOnTargetB,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _DualStatBar — proportional bars with a value on each side (centre-meeting).
// ---------------------------------------------------------------------------

class _DualStatBar extends StatelessWidget {
  final String label;
  final int leftVal;
  final int rightVal;
  final String leftSuffix;
  final String rightSuffix;

  const _DualStatBar({
    required this.label,
    required this.leftVal,
    required this.rightVal,
    this.leftSuffix = '',
    this.rightSuffix = '',
  });

  @override
  Widget build(BuildContext context) {
    final total = leftVal + rightVal;
    final leftRatio = total > 0 ? leftVal / total : 0.5;
    final rightRatio = total > 0 ? rightVal / total : 0.5;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 11,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                '$leftVal$leftSuffix',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Left bar fills toward the centre (right-to-left via Directionality).
            Expanded(
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: leftRatio,
                    minHeight: 5,
                    backgroundColor: Colors.white10,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white54,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: rightRatio,
                  minHeight: 5,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Colors.white54,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 34,
              child: Text(
                '$rightVal$rightSuffix',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
