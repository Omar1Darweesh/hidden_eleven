import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/tournament/widgets/event_phase_banner.dart';

void main() {
  Widget harness(Widget child) =>
      MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: child));

  testWidgets('renders icon, title, and subtitle', (tester) async {
    await tester.pumpWidget(
      harness(
        const EventPhaseBanner(
          accent: Colors.amber,
          icon: Icons.how_to_reg,
          title: 'READY CHECK',
          subtitle: '2 of 4 managers ready',
        ),
      ),
    );

    expect(find.byIcon(Icons.how_to_reg), findsOneWidget);
    expect(find.text('READY CHECK'), findsOneWidget);
    expect(find.text('2 of 4 managers ready'), findsOneWidget);
  });

  testWidgets('renders optional trailing, titleTrailing, and body slots', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        EventPhaseBanner(
          accent: Colors.amber,
          icon: Icons.how_to_reg,
          title: 'READY CHECK',
          titleTrailing: const Icon(Icons.help_outline, key: Key('title-trailing')),
          trailing: const Text('01:59', key: Key('trailing')),
          body: const Text('body content', key: Key('body')),
        ),
      ),
    );

    expect(find.byKey(const Key('title-trailing')), findsOneWidget);
    expect(find.byKey(const Key('trailing')), findsOneWidget);
    expect(find.byKey(const Key('body')), findsOneWidget);
  });

  testWidgets('omits optional slots cleanly when not provided', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        const EventPhaseBanner(
          accent: Colors.amber,
          icon: Icons.emoji_events,
          title: 'TOURNAMENT COMPLETE',
        ),
      ),
    );

    expect(find.text('TOURNAMENT COMPLETE'), findsOneWidget);
  });
}
