import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import '../models/tournament_models.dart';

/// One row in the match-center-style event timeline: the minute (or penalty
/// kick number) sits in a shared central rail, and the event content renders
/// on the LEFT when it belongs to [match]'s participantA and on the RIGHT
/// when it belongs to participantB — the same layout convention as a real
/// football live-match center, so it's obvious at a glance which team an
/// event belongs to without reading team names.
class TournamentEventFeedItem extends StatelessWidget {
  final LiveMatchEvent event;
  final bool isTeamA;

  const TournamentEventFeedItem({
    super.key,
    required this.event,
    required this.isTeamA,
  });

  bool get _isRed => event.type == 'red_card';
  bool get _isGoal => event.type == 'goal';
  bool get _isPenalty =>
      event.type == 'penalty_scored' || event.type == 'penalty_missed';

  Color get _eventColor => switch (event.type) {
    'goal' => HETheme.pfSuccess,
    'yellow_card' => HETheme.pfWarning,
    'red_card' => HETheme.pfDanger,
    'big_chance_missed' => HETheme.pfGold,
    'penalty_scored' => HETheme.pfSuccess,
    'penalty_missed' => HETheme.pfDanger,
    _ => Colors.white38,
  };

  String get _icon => switch (event.type) {
    'goal' => '⚽',
    'yellow_card' => '🟨',
    'red_card' => '🟥',
    'big_chance_missed' => '💨',
    'penalty_scored' => '⚽',
    'penalty_missed' => '❌',
    _ => '•',
  };

  String get _typeLabel => switch (event.type) {
    'goal' => 'Goal',
    'yellow_card' => 'Yellow Card',
    'red_card' => 'Red Card',
    'big_chance_missed' => 'Big Chance Missed',
    'penalty_scored' => 'Penalty Scored',
    'penalty_missed' => 'Penalty Missed',
    _ => event.type,
  };

  /// Server marks shootout kicks as minute 120 + kick number (see
  /// MatchEvent.minute doc) — shown as "P1", "P2", … rather than a real
  /// minute.
  String get _minuteLabel =>
      _isPenalty ? 'P${event.minute - 120}' : "${event.minute}'";

  @override
  Widget build(BuildContext context) {
    final content = _EventContent(
      event: event,
      alignEnd: !isTeamA,
      color: _eventColor,
      icon: _icon,
      typeLabel: _typeLabel,
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 5),
      // Red cards get a subtle full-row tint (side-agnostic — a directional
      // border wouldn't make sense once events can sit on either side).
      decoration: _isRed
          ? BoxDecoration(
              color: HETheme.pfDanger.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6),
            )
          : null,
      // IntrinsicHeight gives the Row below a definite height to stretch
      // into — a plain Row(crossAxisAlignment: stretch) inside a Column's
      // unbounded height context throws (infinite constraint), which is
      // exactly why this needs to be explicit rather than left implicit.
      child: IntrinsicHeight(
        child: Row(
          // Stretch so the central spine (below) always spans this row's full
          // height, however tall the content on either side is (e.g. a goal
          // with an assist line is taller than a plain card event).
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Home team (participantA) — left column. Top-right-anchored
            // against the centre rail so short entries still read as
            // "belonging" to this side and line up with the minute bubble,
            // rather than floating centred in empty space.
            Expanded(
              child: Align(
                alignment: Alignment.topRight,
                child: isTeamA ? content : const SizedBox.shrink(),
              ),
            ),

            // Shared central rail: a continuous vertical spine (positioned to
            // span this row's full stretched height; consecutive rows touch,
            // reading as one line down the whole panel) with the minute/kick
            // bubble + score badge on top — the classic "match center" divider
            // between the two team sides.
            SizedBox(
              width: 46,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  const Positioned(
                    top: 0,
                    bottom: 0,
                    left: 22,
                    child: SizedBox(
                      width: 2,
                      child: ColoredBox(color: Colors.white12),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: HETheme.pfBgVoid,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _eventColor.withValues(alpha: 0.6),
                            width: _isRed ? 2 : 1.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _minuteLabel,
                          style: TextStyle(
                            color: _eventColor,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (_isGoal)
                        Container(
                          margin: const EdgeInsets.only(top: 3),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: HETheme.pfBgVoid,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${event.currentScoreA}–${event.currentScoreB}',
                            style: const TextStyle(
                              color: HETheme.pfSuccess,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // Away team (participantB) — right column. Top-left-anchored
            // against the centre rail for the same reason as the home column.
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: !isTeamA ? content : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _EventContent — the icon/name/assist block, block-aligned to the correct
// side (normal reading order preserved, matching the convention already used
// for the collapsed card's per-team facts — only the block position mirrors).
// ---------------------------------------------------------------------------

class _EventContent extends StatelessWidget {
  final LiveMatchEvent event;
  final bool alignEnd;
  final Color color;
  final String icon;
  final String typeLabel;

  const _EventContent({
    required this.event,
    required this.alignEnd,
    required this.color,
    required this.icon,
    required this.typeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final crossAlign = alignEnd
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final textAlign = alignEnd ? TextAlign.right : TextAlign.left;

    return Column(
      crossAxisAlignment: crossAlign,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: alignEnd
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                '$typeLabel — ${event.playerName}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                ),
                textAlign: textAlign,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (event.assistPlayerName != null)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              'Assist: ${event.assistPlayerName}',
              style: const TextStyle(color: Colors.white38, fontSize: 10.5),
              textAlign: textAlign,
            ),
          ),
      ],
    );
  }
}
