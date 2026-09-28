import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/shared/widgets/hex_progress_ring.dart';

void main() {
  Widget harness(Widget child) =>
      MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: child));

  testWidgets('renders current/total and a matching Semantics label', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        const HexProgressRing(current: 2, total: 4, color: Colors.amber),
      ),
    );

    expect(find.text('2/4'), findsOneWidget);
    final semantics = tester.getSemantics(find.byType(HexProgressRing));
    expect(semantics.label, '2 of 4 ready');
  });

  testWidgets('0 of 0 does not throw (no division by zero)', (tester) async {
    await tester.pumpWidget(
      harness(const HexProgressRing(current: 0, total: 0, color: Colors.amber)),
    );

    expect(find.text('0/0'), findsOneWidget);
  });

  testWidgets('current == total renders without error (fully ready)', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(const HexProgressRing(current: 3, total: 3, color: Colors.amber)),
    );

    expect(find.text('3/3'), findsOneWidget);
  });
}
