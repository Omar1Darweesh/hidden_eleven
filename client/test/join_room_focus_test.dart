import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/join/join_room_screen.dart';

/// Regression tests for the P0 "room code field loses focus after every
/// character" bug.
///
/// Root cause was a `ValueKey(_lastLength)` on the keystroke-pulse
/// `TweenAnimationBuilder` wrapping the field: bumping it per character
/// remounted the whole subtree, destroying the `TextField`'s `EditableText`
/// state (and, on web, its browser input connection) so focus/keyboard were
/// dropped every keystroke. The pulse is now controller-driven and never
/// changes widget identity.
void main() {
  Future<void> pumpJoin(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: JoinRoomScreen(displayName: 'QA')),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'a full 6-letter code can be typed continuously without re-focusing, and '
    'the field keeps focus throughout',
    (tester) async {
      await pumpJoin(tester);

      final field = find.byType(TextField);
      expect(field, findsOneWidget);

      // Focus once, the way a user taps the field once.
      await tester.tap(field);
      await tester.pump();

      // Type one character at a time, never re-tapping, asserting focus
      // survives each keystroke — this is the exact failure the user hit.
      const code = 'ABCDEF';
      for (var i = 0; i < code.length; i++) {
        await tester.enterText(field, code.substring(0, i + 1));
        await tester.pump();

        final editable = tester.widget<EditableText>(
          find.byType(EditableText),
        );
        expect(
          editable.focusNode.hasFocus,
          isTrue,
          reason: 'focus lost after typing character ${i + 1} ("${code[i]}")',
        );
      }

      expect(find.text(code), findsOneWidget);
    },
  );

  testWidgets(
    'typing does not remount the field — the EditableText State object is '
    'preserved across keystrokes',
    (tester) async {
      await pumpJoin(tester);
      final field = find.byType(TextField);

      await tester.enterText(field, 'A');
      await tester.pump();
      final stateBefore = tester.state(find.byType(EditableText));

      await tester.enterText(field, 'AB');
      await tester.pump();
      final stateAfter = tester.state(find.byType(EditableText));

      // Identity, not equality: a remount would produce a different State.
      expect(identical(stateBefore, stateAfter), isTrue);
    },
  );

  testWidgets(
    'under reduced motion the keystroke pulse is skipped and typing still '
    'works with no pending timers',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: MaterialApp(home: JoinRoomScreen(displayName: 'QA')),
          ),
        ),
      );
      await tester.pump();

      final field = find.byType(TextField);
      await tester.enterText(field, 'ABCDEF');
      await tester.pump();

      expect(find.text('ABCDEF'), findsOneWidget);
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.focusNode.hasFocus, isTrue);
    },
  );
}
