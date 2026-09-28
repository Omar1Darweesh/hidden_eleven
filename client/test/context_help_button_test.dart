import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/admin/models/admin_models.dart';
import 'package:hidden_eleven/features/game/models/chemistry_vars.dart';
import 'package:hidden_eleven/shared/widgets/context_help_button.dart';

AdminContextHelp _help(String body) => AdminContextHelp(
  key: 'draft_scoring',
  title: 'Draft & Scoring',
  visible: true,
  sections: [
    AdminContextHelpSection(
      heading: 'SCORING',
      entries: [AdminContextHelpEntry(label: 'Line Leaders', body: body)],
    ),
  ],
);

void main() {
  setUp(() {
    ChemistryVars.debugOverrideValues(null);
  });

  group('contextHelpToSections — D5 placeholder resolution', () {
    test('a known placeholder resolves against live ChemistryVars values', () {
      ChemistryVars.debugOverrideValues({'lineLeaderBonus': 8});
      final sections = contextHelpToSections(
        _help('Line leaders earn +{lineLeaderBonus} each.'),
      );

      expect(sections, hasLength(1));
      expect(sections.first.entries, hasLength(1));
      expect(sections.first.entries.first.body, 'Line leaders earn +8 each.');
    });

    test('falls back to the v1 default before any config is loaded', () {
      final sections = contextHelpToSections(
        _help('Line leaders earn +{lineLeaderBonus} each.'),
      );

      expect(sections.first.entries.first.body, 'Line leaders earn +2 each.');
    });

    test(
      'an unknown placeholder degrades safely, does not crash conversion',
      () {
        expect(
          () => contextHelpToSections(_help('Bonus: {notARealVariable}.')),
          returnsNormally,
        );
        final sections = contextHelpToSections(
          _help('Bonus: {notARealVariable}.'),
        );
        expect(sections.first.entries.first.body, 'Bonus: —.');
      },
    );

    test('heading and label are passed through unchanged (not resolved)', () {
      final sections = contextHelpToSections(_help('plain text, no tokens'));
      expect(sections.first.title, 'SCORING');
      expect(sections.first.entries.first.label, 'Line Leaders');
    });
  });
}
