import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/game/models/chemistry_vars.dart';

void main() {
  setUp(() {
    // Every test starts from "not yet loaded" (fallback values), regardless
    // of what a previous test simulated via debugOverrideValues.
    ChemistryVars.debugOverrideValues(null);
  });

  group('resolve — fallback state (before ensureLoaded() ever succeeds)', () {
    test('substitutes all 7 known placeholders with the v1 defaults', () {
      const template =
          '{challengeReward} {tierEasyReward} {tierMediumReward} '
          '{tierHardReward} {lineLeaderBonus} {yellowPenalty} '
          '{captainMultiplier}';
      // v1 defaults mirror DEFAULT_SCORING_CONFIG_V1 (scoring-config.ts)
      // exactly: rewardPerChallenge 5, tierRewards 2/4/6, bonusPerLine 2,
      // yellowPenalty 20, captainMultiplier 2.
      expect(ChemistryVars.resolve(template), '5 2 4 6 2 20 2');
    });

    test('a template with no placeholders is returned unchanged', () {
      const template = 'Pick one of YOUR players to captain.';
      expect(ChemistryVars.resolve(template), template);
    });

    test(
      'an unknown placeholder degrades to a marker, not the raw token or a crash',
      () {
        expect(
          () => ChemistryVars.resolve('Bonus: {notARealVariable}'),
          returnsNormally,
        );
        expect(ChemistryVars.resolve('Bonus: {notARealVariable}'), 'Bonus: —');
      },
    );

    test(
      'a template mixing known and unknown placeholders resolves the known one and marks the unknown one',
      () {
        final result = ChemistryVars.resolve(
          '+{lineLeaderBonus} per line, {bogus} elsewhere',
        );
        expect(result, '+2 per line, — elsewhere');
      },
    );

    test(
      'malformed placeholder syntax (no closing brace) is left untouched, not crashed on',
      () {
        const template = 'Docks {yellowPenalty points (missing brace)';
        expect(() => ChemistryVars.resolve(template), returnsNormally);
        expect(ChemistryVars.resolve(template), template);
      },
    );
  });

  group('resolve — loaded state (simulated via debugOverrideValues)', () {
    test('uses the configured value instead of the v1 default once loaded', () {
      ChemistryVars.debugOverrideValues({'lineLeaderBonus': 5});
      expect(
        ChemistryVars.resolve('+{lineLeaderBonus} per line'),
        '+5 per line',
      );
    });

    test(
      'a placeholder missing from the configured map still falls back to its v1 default',
      () {
        // Simulates a partially-parsed server response — one field present,
        // the rest absent — none of the other 6 placeholders should break.
        ChemistryVars.debugOverrideValues({'lineLeaderBonus': 5});
        expect(ChemistryVars.resolve('{yellowPenalty}'), '20');
        expect(ChemistryVars.resolve('{captainMultiplier}'), '2');
      },
    );

    test('resetting to null returns to fallback behavior', () {
      ChemistryVars.debugOverrideValues({'lineLeaderBonus': 999});
      expect(ChemistryVars.resolve('{lineLeaderBonus}'), '999');
      ChemistryVars.debugOverrideValues(null);
      expect(ChemistryVars.resolve('{lineLeaderBonus}'), '2');
    });
  });

  group('ensureLoaded — swallows fetch failures', () {
    test(
      'never throws even when the server is unreachable, and fallback values keep working',
      () async {
        // No server is running in the test sandbox, so this exercises the
        // real try/catch path (connection failure), not a mocked one — the
        // same contract AbilityMeta.ensureLoaded()/CardTier.ensureLoaded()
        // already rely on with zero test coverage of their own.
        await expectLater(ChemistryVars.ensureLoaded(), completes);
        // Since the fetch could not have succeeded, resolve() must still be
        // fully functional off the fallback map.
        expect(ChemistryVars.resolve('{yellowPenalty}'), '20');
      },
    );

    test(
      'calling ensureLoaded() repeatedly is safe (idempotent guard)',
      () async {
        await ChemistryVars.ensureLoaded();
        await expectLater(ChemistryVars.ensureLoaded(), completes);
      },
    );
  });

  group('findUnknownPlaceholders — D5 admin save-time warning', () {
    test('a template using only known placeholders reports nothing', () {
      const template = 'Docks {yellowPenalty} points, ×{captainMultiplier}.';
      expect(ChemistryVars.findUnknownPlaceholders(template), isEmpty);
    });

    test('a plain template with no placeholders reports nothing', () {
      expect(
        ChemistryVars.findUnknownPlaceholders('No placeholders here.'),
        isEmpty,
      );
    });

    test('a typo\'d placeholder is reported by name', () {
      expect(
        ChemistryVars.findUnknownPlaceholders('Docks {yellowPenaltyy} points.'),
        ['yellowPenaltyy'],
      );
    });

    test(
      'reports every distinct unknown name, but never duplicates one that repeats',
      () {
        const template =
            '{foo} and {bar} and {foo} again, plus {yellowPenalty}.';
        expect(ChemistryVars.findUnknownPlaceholders(template), ['foo', 'bar']);
      },
    );

    test(
      'is case-sensitive — a differently-cased known name is still unknown',
      () {
        expect(ChemistryVars.findUnknownPlaceholders('{YellowPenalty}'), [
          'YellowPenalty',
        ]);
      },
    );
  });
}
