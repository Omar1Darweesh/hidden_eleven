import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/tournament/widgets/fixture_capsule.dart';

Future<void> _pump(WidgetTester tester, Widget child, {double width = 375}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: Center(child: SizedBox(width: width, child: child))),
      ),
    );

void main() {
  group('FixtureState — meaning is never carried by colour alone', () {
    for (final state in FixtureState.values) {
      testWidgets('${state.name} renders both its icon and its text label', (
        tester,
      ) async {
        await _pump(tester, FixtureStateTag(state: state));

        expect(find.text(state.label), findsOneWidget);
        expect(find.byIcon(state.icon), findsOneWidget);
      });
    }

    test('every state defines a distinct label', () {
      final labels = FixtureState.values.map((s) => s.label).toSet();
      // finalSet/complete intentionally differ; all seven must be tellable
      // apart by text alone.
      expect(labels.length, FixtureState.values.length);
    });

    test('only the knocked-out state dims its content', () {
      for (final s in FixtureState.values) {
        expect(s.isDimmed, s == FixtureState.out, reason: s.name);
      }
    });
  });

  testWidgets('renders its child at every emphasis level', (tester) async {
    for (final emphasis in FixtureEmphasis.values) {
      await _pump(
        tester,
        FixtureCapsule(
          emphasis: emphasis,
          state: FixtureState.scheduled,
          child: const Text('Fixture'),
        ),
      );
      expect(find.text('Fixture'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: emphasis.name);
    }
  });

  testWidgets('the OUT state dims the capsule as well as labelling it', (
    tester,
  ) async {
    await _pump(
      tester,
      const FixtureCapsule(
        state: FixtureState.out,
        child: Text('Knocked out'),
      ),
    );

    // Dimming *and* an explicit state — never dimming alone (the tag is
    // rendered by callers alongside; here we assert the dimming half).
    expect(
      find.descendant(
        of: find.byType(FixtureCapsule),
        matching: find.byType(Opacity),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a tappable capsule meets the 44px minimum target height', (
    tester,
  ) async {
    await _pump(
      tester,
      FixtureCapsule(
        state: FixtureState.scheduled,
        onTap: () {},
        padding: EdgeInsets.zero,
        child: const Text('Tap me'),
      ),
    );

    final size = tester.getSize(find.byType(FixtureCapsule));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('a tap reaches the callback', (tester) async {
    var tapped = false;
    await _pump(
      tester,
      FixtureCapsule(
        state: FixtureState.scheduled,
        onTap: () => tapped = true,
        child: const Text('Tap me'),
      ),
    );
    await tester.tap(find.text('Tap me'));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('a long participant name ellipsises instead of overflowing', (
    tester,
  ) async {
    await _pump(
      tester,
      const FixtureCapsule(
        state: FixtureState.scheduled,
        child: Text(
          'A Preposterously Long Participant Name That Cannot Possibly Fit',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      width: 160,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('exposes a semantic label when given one', (tester) async {
    await _pump(
      tester,
      const FixtureCapsule(
        state: FixtureState.live,
        semanticLabel: 'Alpha versus Beta, live',
        child: Text('A v B'),
      ),
    );

    final semantics = tester.getSemantics(find.byType(FixtureCapsule));
    expect(semantics.label, 'Alpha versus Beta, live');
  });

  testWidgets('state tags stay readable at XL text scale', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                child: FixtureStateTag(state: FixtureState.finalSet),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('FINAL SET'), findsOneWidget);
  });
}
