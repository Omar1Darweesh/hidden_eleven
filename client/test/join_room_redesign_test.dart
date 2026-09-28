import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hidden_eleven/features/join/join_room_screen.dart';

Widget harness({double textScale = 1.0}) => ProviderScope(
  child: MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: const JoinRoomScreen(displayName: 'Alice'),
  ),
);

void main() {
  group('Join Room — code entry preserved behavior', () {
    testWidgets('shows the 6-letter room code field and both actions', (
      tester,
    ) async {
      await tester.pumpWidget(harness());
      await tester.pump();

      expect(find.text('ROOM CODE'), findsOneWidget);
      expect(find.text('Join Room'), findsOneWidget);
      expect(find.text('Watch Only'), findsOneWidget);
    });

    testWidgets(
      'rejects non-letter characters via the existing input formatter',
      (tester) async {
        await tester.pumpWidget(harness());
        await tester.pump();

        await tester.enterText(find.byType(TextField), 'AB12CD');
        await tester.pump();

        expect(find.text('ABCD'), findsOneWidget);
      },
    );
  });

  group('Join Room — keyboard focus visibility', () {
    testWidgets('code field shows a brighter cyan ring while focused', (
      tester,
    ) async {
      await tester.pumpWidget(harness());
      await tester.pump();

      // autofocus: true means the field starts focused already.
      final containerBefore = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      final borderBefore =
          (containerBefore.decoration as BoxDecoration).border as Border;
      expect(borderBefore.top.width, 2); // focused width

      // Move focus away — border should relax back to the unfocused width.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      final containerAfter = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      final borderAfter =
          (containerAfter.decoration as BoxDecoration).border as Border;
      expect(borderAfter.top.width, 1.5); // unfocused width
    });
  });

  group('Join Room — large text scale', () {
    testWidgets('does not overflow at XL text scale', (tester) async {
      await tester.pumpWidget(harness(textScale: 1.3));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('ROOM CODE'), findsOneWidget);
      expect(find.text('Join Room'), findsOneWidget);
    });

    testWidgets('the code field opts out of ambient text scaling', (
      tester,
    ) async {
      await tester.pumpWidget(harness(textScale: 1.3));
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      final scalerMediaQuery = tester.widget<MediaQuery>(
        find
            .ancestor(
              of: find.byType(TextField),
              matching: find.byType(MediaQuery),
            )
            .first,
      );
      expect(scalerMediaQuery.data.textScaler, TextScaler.noScaling);
      expect(field.style?.fontSize, 32);
    });
  });
}
