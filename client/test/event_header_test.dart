import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/tournament/widgets/event_header.dart';

Future<void> _pump(
  WidgetTester tester, {
  double width = 1280,
  double textScale = 1.0,
  bool compact = false,
  String roundLabel = 'Semi-finals',
  String? status = 'Ready check',
  Widget? pips,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: EventHeader(
                roundLabel: roundLabel,
                status: status,
                statusIcon: Icons.schedule_rounded,
                compact: compact,
                pips: pips,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows the event eyebrow, round headline and status', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('TOURNAMENT NIGHT'), findsOneWidget);
    expect(find.text('Semi-finals'), findsOneWidget);
    expect(find.text('Ready check'), findsOneWidget);
  });

  testWidgets('renders caller-supplied round pips', (tester) async {
    await _pump(tester, pips: const Text('PIPS'));
    expect(find.text('PIPS'), findsOneWidget);
  });

  testWidgets('omits the status line entirely when there is none', (
    tester,
  ) async {
    await _pump(tester, status: null);
    expect(find.text('Ready check'), findsNothing);
    expect(find.text('Semi-finals'), findsOneWidget);
  });

  testWidgets('announces event, round and status as one header', (
    tester,
  ) async {
    await _pump(tester);

    final semantics = tester.getSemantics(find.byType(EventHeader));
    expect(semantics.label, contains('TOURNAMENT NIGHT'));
    expect(semantics.label, contains('Semi-finals'));
    expect(semantics.label, contains('Ready check'));
  });

  testWidgets('does not overflow at any supported width', (tester) async {
    for (final w in <double>[1280, 1024, 768, 720, 700, 414, 390, 375, 360]) {
      await _pump(tester, width: w, compact: w < 700);
      expect(tester.takeException(), isNull, reason: 'overflow at ${w}px');
    }
  });

  testWidgets('does not overflow at XL text scale on a 360px screen', (
    tester,
  ) async {
    await _pump(tester, width: 360, compact: true, textScale: 1.3);
    expect(tester.takeException(), isNull);
    expect(find.text('Semi-finals'), findsOneWidget);
  });

  testWidgets('a very long round label truncates rather than overflowing', (
    tester,
  ) async {
    await _pump(
      tester,
      width: 360,
      compact: true,
      roundLabel: 'Quarter-finals Second Leg Replay Decider',
    );
    expect(tester.takeException(), isNull);
  });
}
