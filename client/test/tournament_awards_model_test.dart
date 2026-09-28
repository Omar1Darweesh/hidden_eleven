import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/tournament/models/tournament_awards_model.dart';

/// Track A Step 5 — pointsConfig parsing and consumption. Mirrors the
/// codebase's existing model-test style (plain JSON fixtures, no widget
/// pumping needed for a pure data model).
void main() {
  Map<String, dynamic> championJson(String id) => {
    'participantId': id,
    'kind': 'real',
    'displayName': id.toUpperCase(),
    'overallRating': 80.0,
  };

  Map<String, dynamic> awardsJson({
    required String championId,
    required String runnerUpId,
    Map<String, dynamic>? pointsConfig,
    Map<String, dynamic>? pointsAwarded,
    List<dynamic>? topScorer,
  }) => {
    'champion': championJson(championId),
    'runnerUp': championJson(runnerUpId),
    'topScorer': topScorer ?? const [],
    'mostAssists': const [],
    'topContributions': const [],
    'highestAvgRating': const [],
    'cleanSheets': const [],
    'blockedCategories': const [],
    'pointsAwarded': pointsAwarded ?? {},
    if (pointsConfig != null) 'pointsConfig': pointsConfig,
  };

  test('parses pointsConfig from the server payload', () {
    final awards = TournamentAwardsModel.fromJson(
      awardsJson(
        championId: 'p1',
        runnerUpId: 'p2',
        pointsConfig: {
          'championPoints': 111,
          'runnerUpPoints': 222,
          'topScorerBonus': 333,
          'mostAssistsBonus': 444,
          'highestRatingBonus': 555,
        },
      ),
    );

    expect(awards.pointsConfig.championPoints, 111);
    expect(awards.pointsConfig.runnerUpPoints, 222);
    expect(awards.pointsConfig.topScorerBonus, 333);
    expect(awards.pointsConfig.mostAssistsBonus, 444);
    expect(awards.pointsConfig.highestRatingBonus, 555);
  });

  test(
    'breakdownFor uses the parsed pointsConfig values, not any hardcoded constant',
    () {
      final awards = TournamentAwardsModel.fromJson(
        awardsJson(
          championId: 'p1',
          runnerUpId: 'p2',
          pointsConfig: {
            'championPoints': 777,
            'runnerUpPoints': 333,
            'topScorerBonus': 10,
            'mostAssistsBonus': 10,
            'highestRatingBonus': 10,
          },
        ),
      );

      final championLines = awards.breakdownFor('p1');
      expect(championLines, hasLength(1));
      expect(championLines.first.label, 'Champion');
      expect(championLines.first.points, 777);

      final runnerUpLines = awards.breakdownFor('p2');
      expect(runnerUpLines, hasLength(1));
      expect(runnerUpLines.first.label, 'Runner-up');
      expect(runnerUpLines.first.points, 333);
    },
  );

  test(
    'a shared Top Scorer split uses pointsConfig.topScorerBonus as the pool',
    () {
      final awards = TournamentAwardsModel.fromJson(
        awardsJson(
          championId: 'p1',
          runnerUpId: 'p2',
          pointsConfig: {
            'championPoints': 0,
            'runnerUpPoints': 0,
            'topScorerBonus': 101, // odd, so rounding-up is exercised
            'mostAssistsBonus': 0,
            'highestRatingBonus': 0,
          },
          topScorer: [
            {
              'playerName': 'a',
              'participantId': 'p1',
              'goals': 3,
              'minutesPlayed': 90,
            },
            {
              'playerName': 'b',
              'participantId': 'p2',
              'goals': 3,
              'minutesPlayed': 90,
            },
          ],
        ),
      );

      final lines = awards.breakdownFor('p1');
      final topScorerLine = lines.firstWhere((l) => l.label == 'Top Scorer');
      // 101 split 2 ways, rounded up → 51 each.
      expect(topScorerLine.points, 51);
      expect(topScorerLine.shared, isTrue);
    },
  );

  test(
    'missing pointsConfig falls back to the legacy hardcoded values, preserving today\'s display exactly',
    () {
      final awards = TournamentAwardsModel.fromJson(
        awardsJson(
          championId: 'p1',
          runnerUpId: 'p2',
        ), // no pointsConfig key at all
      );

      expect(awards.pointsConfig.championPoints, 50);
      expect(awards.pointsConfig.runnerUpPoints, 20);
      expect(awards.pointsConfig.topScorerBonus, 15);
      expect(awards.pointsConfig.mostAssistsBonus, 10);
      expect(awards.pointsConfig.highestRatingBonus, 10);

      final championLines = awards.breakdownFor('p1');
      expect(championLines.first.points, 50);
      final runnerUpLines = awards.breakdownFor('p2');
      expect(runnerUpLines.first.points, 20);
    },
  );

  test(
    'a default-config (v1) payload produces identical breakdown output to the pre-Track-A hardcoded behavior',
    () {
      final awards = TournamentAwardsModel.fromJson(
        awardsJson(
          championId: 'p1',
          runnerUpId: 'p2',
          pointsConfig: {
            'championPoints': 50,
            'runnerUpPoints': 20,
            'topScorerBonus': 15,
            'mostAssistsBonus': 10,
            'highestRatingBonus': 10,
          },
          topScorer: [
            {
              'playerName': 'a',
              'participantId': 'p1',
              'goals': 3,
              'minutesPlayed': 90,
            },
          ],
        ),
      );

      final lines = awards.breakdownFor('p1');
      expect(lines.map((l) => l.display).toList(), [
        'Champion +50',
        'Top Scorer +15',
      ]);
    },
  );
}
