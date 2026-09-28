import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/shared/widgets/segmented_bar.dart';

void main() {
  Widget harness(Widget child) =>
      MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: child));

  testWidgets('renders a legend entry for every segment, in order', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        const SegmentedBar(
          segments: [
            BarSegment(label: 'Champion', color: Colors.amber, value: 50),
            BarSegment(label: 'Top Scorer', color: Colors.blue, value: 15),
          ],
        ),
      ),
    );

    expect(find.text('Champion'), findsOneWidget);
    expect(find.text('+50'), findsOneWidget);
    expect(find.text('Top Scorer'), findsOneWidget);
    expect(find.text('+15'), findsOneWidget);
  });

  testWidgets(
    'a value <= 0 draws no bar width but still appears in the legend',
    (tester) async {
      await tester.pumpWidget(
        harness(
          const SegmentedBar(
            segments: [
              BarSegment(label: 'Base', color: Colors.grey, value: 100),
              BarSegment(label: 'Penalty', color: Colors.red, value: -5),
            ],
          ),
        ),
      );

      expect(find.text('Base'), findsOneWidget);
      expect(find.text('+100'), findsOneWidget);
      expect(find.text('Penalty'), findsOneWidget);
      expect(find.text('-5'), findsOneWidget);
    },
  );

  testWidgets('all segments <= 0 renders the empty-track fallback, not a '
      'crash or an invisible zero-height bar', (tester) async {
    await tester.pumpWidget(
      harness(
        const SegmentedBar(
          segments: [BarSegment(label: 'Nothing yet', color: Colors.grey, value: 0)],
        ),
      ),
    );

    expect(find.text('Nothing yet'), findsOneWidget);
    expect(find.byType(SegmentedBar), findsOneWidget);
  });
}
