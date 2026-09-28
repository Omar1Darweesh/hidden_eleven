import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/widgets/card_acquired_reveal.dart';

const _card = CandidateCard(
  cardId: 'c1',
  playerName: 'Ada Okafor',
  basePositionType: 'ST',
  rating: 87,
  club: 'Arsenal',
);

Future<void> _pump(
  WidgetTester tester, {
  bool reduced = false,
  VoidCallback? onDismiss,
  CandidateCard card = _card,
  double width = 375,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduced, size: Size(width, 800)),
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: CardAcquiredReveal(
                card: card,
                slotLabel: 'ST',
                onDismiss: onDismiss ?? () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows name, rating, position, club and destination slot', (
    tester,
  ) async {
    await _pump(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Ada Okafor'), findsOneWidget);
    expect(find.text('87'), findsOneWidget);
    expect(find.text('ST'), findsOneWidget); // position chip
    expect(find.text('Arsenal'), findsOneWidget);
    expect(find.text('Into ST'), findsOneWidget);
    expect(find.text('SIGNED'), findsOneWidget);

    // Let the self-dismiss timer elapse so no timer outlives the test.
    await tester.pump(kCardAcquiredRevealDuration);
  });

  testWidgets('a card with no club still renders the rest of the confirmation',
      (tester) async {
    await _pump(
      tester,
      card: const CandidateCard(
        cardId: 'c2',
        playerName: 'No Club',
        basePositionType: 'GK',
        rating: 70,
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('No Club'), findsOneWidget);
    expect(find.text('70'), findsOneWidget);
    expect(find.text('Into ST'), findsOneWidget);

    await tester.pump(kCardAcquiredRevealDuration);
  });

  testWidgets('tapping dismisses immediately', (tester) async {
    var dismissed = false;
    await _pump(tester, onDismiss: () => dismissed = true);
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Ada Okafor'));
    await tester.pump();

    expect(dismissed, isTrue);
    await tester.pump(kCardAcquiredRevealDuration);
  });

  testWidgets('self-dismisses after its own duration', (tester) async {
    var dismissed = false;
    await _pump(tester, onDismiss: () => dismissed = true);
    await tester.pump(const Duration(milliseconds: 400));
    expect(dismissed, isFalse, reason: 'must stay long enough to be read');

    await tester.pump(kCardAcquiredRevealDuration);
    expect(dismissed, isTrue);
  });

  testWidgets(
    'reduced motion renders the final composition immediately, with the same '
    'content and the same dismiss timing',
    (tester) async {
      var dismissed = false;
      await _pump(tester, reduced: true, onDismiss: () => dismissed = true);

      // No pumping past an entrance animation: everything is already at its
      // end state on the first frame.
      await tester.pump();
      expect(find.text('Ada Okafor'), findsOneWidget);
      expect(find.text('Into ST'), findsOneWidget);

      final fade = tester.widget<FadeTransition>(
        find.byType(FadeTransition).first,
      );
      expect(fade.opacity.value, 1.0);

      await tester.pump(kCardAcquiredRevealDuration);
      expect(dismissed, isTrue);
    },
  );

  testWidgets('does not overflow at 375px or 360px', (tester) async {
    for (final width in <double>[375, 360]) {
      await _pump(tester, width: width);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
      await tester.pump(kCardAcquiredRevealDuration);
    }
  });

  testWidgets('announces the acquisition to screen readers', (tester) async {
    await _pump(tester);
    await tester.pump(const Duration(milliseconds: 400));

    final semantics = tester.getSemantics(find.byType(CardAcquiredReveal));
    expect(semantics.label, contains('Ada Okafor'));
    expect(semantics.label, contains('87'));
    expect(semantics.label, contains('into ST'));

    await tester.pump(kCardAcquiredRevealDuration);
  });
}
