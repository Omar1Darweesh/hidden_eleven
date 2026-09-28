import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/game/models/ability.dart';
import 'package:hidden_eleven/features/game/models/chemistry_vars.dart';

void main() {
  setUp(() {
    AbilityMeta.debugOverrideConfigured(null);
    ChemistryVars.debugOverrideValues(null);
  });

  group(
    'AbilityMeta.of — fallback state (before ensureLoaded() ever succeeds)',
    () {
      test(
        'returns the built-in name/description/color/icon for every type',
        () {
          final meta = AbilityMeta.of(AbilityType.yellow);
          expect(meta.name, 'Yellow Card');
          expect(meta.description, 'Knock 20 points off a rival’s score.');
          expect(meta.color, const Color(0xFFF2C037));
          expect(meta.icon, Icons.style_rounded);
        },
      );
    },
  );

  group(
    'AbilityMeta.of — loaded state (simulated via debugOverrideConfigured)',
    () {
      test(
        'returns server-loaded name/description/color once configured data exists',
        () {
          AbilityMeta.debugOverrideConfigured({
            AbilityType.yellow: (
              name: 'Caution Card',
              description: 'Docks {yellowPenalty} points from a rival.',
              color: const Color(0xFFABCDEF),
            ),
          });

          final meta = AbilityMeta.of(AbilityType.yellow);
          expect(meta.name, 'Caution Card');
          expect(
            meta.description,
            'Docks {yellowPenalty} points from a rival.',
          );
          expect(meta.color, const Color(0xFFABCDEF));
        },
      );

      test('icon always comes from the built-in table, never the server', () {
        AbilityMeta.debugOverrideConfigured({
          AbilityType.yellow: (
            name: 'Caution Card',
            description: 'Docks points.',
            color: const Color(0xFFABCDEF),
          ),
        });

        expect(AbilityMeta.of(AbilityType.yellow).icon, Icons.style_rounded);
      });

      test(
        'a type missing from the configured map still falls back to its built-in entry',
        () {
          AbilityMeta.debugOverrideConfigured({
            AbilityType.yellow: (
              name: 'Caution Card',
              description: 'Docks points.',
              color: const Color(0xFFABCDEF),
            ),
          });

          final coach = AbilityMeta.of(AbilityType.coach);
          expect(coach.name, 'Coach Card');
          expect(
            coach.description,
            'Add a new position to one of your players.',
          );
        },
      );

      test('resetting to null returns to fallback behavior', () {
        AbilityMeta.debugOverrideConfigured({
          AbilityType.yellow: (
            name: 'Caution Card',
            description: 'Docks points.',
            color: const Color(0xFFABCDEF),
          ),
        });
        expect(AbilityMeta.of(AbilityType.yellow).name, 'Caution Card');

        AbilityMeta.debugOverrideConfigured(null);
        expect(AbilityMeta.of(AbilityType.yellow).name, 'Yellow Card');
      });
    },
  );

  group('ensureLoaded — swallows fetch failures', () {
    test(
      'never throws even when the server is unreachable, and fallback values keep working',
      () async {
        await expectLater(AbilityMeta.ensureLoaded(), completes);
        expect(AbilityMeta.of(AbilityType.captain).name, 'Captain Card');
      },
    );
  });

  group('resolving a server description through ChemistryVars', () {
    test(
      'a placeholder in the server-loaded description resolves against live chemistry values',
      () {
        AbilityMeta.debugOverrideConfigured({
          AbilityType.yellow: (
            name: 'Yellow Card',
            description: 'Docks {yellowPenalty} points from a rival.',
            color: const Color(0xFFF2C037),
          ),
        });
        ChemistryVars.debugOverrideValues({'yellowPenalty': 30});

        final resolved = ChemistryVars.resolve(
          AbilityMeta.of(AbilityType.yellow).description,
        );
        expect(resolved, 'Docks 30 points from a rival.');
      },
    );
  });
}
