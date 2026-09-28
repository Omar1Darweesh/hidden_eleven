import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/app/app.dart';

void main() {
  testWidgets('Home screen renders brand name', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: HiddenElevenApp()));
    // Not `pumpAndSettle()`: Home's `PurpleFloodlightBackground` runs a
    // deliberate, infinite ambient floodlight-breathe animation whenever
    // motion isn't reduced, so `pumpAndSettle()` never actually settles —
    // a bounded pump past the one-shot entrance animations is correct here.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    // The brand name is now carried by the logo mark's own wordmark artwork
    // (no separate duplicate text title) — exposed to assistive tech (and
    // this test) via its Semantics label rather than a literal Text widget.
    expect(find.bySemanticsLabel('Hidden Eleven'), findsOneWidget);
  });
}
