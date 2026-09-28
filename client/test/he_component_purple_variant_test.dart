import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hidden_eleven/app/theme.dart';
import 'package:hidden_eleven/shared/widgets/he_button.dart';
import 'package:hidden_eleven/shared/widgets/he_text_field.dart';
import 'package:hidden_eleven/shared/widgets/he_visual_style.dart';

Widget wrap(Widget child) => MaterialApp(
  theme: buildAppTheme(),
  home: Scaffold(body: child),
);

void main() {
  group('HEButton — default style is unchanged', () {
    testWidgets('primary button with no style param renders ElevatedButton '
        'using the existing HEColors palette', (tester) async {
      await tester.pumpWidget(
        wrap(HEButton(label: 'Host a Room', onPressed: () {})),
      );

      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      final bg = button.style?.backgroundColor?.resolve({});
      // Unset backgroundColor (color: null, enabled) falls through to the
      // app-wide ElevatedButtonTheme (theme.dart, Night Tactics violet) —
      // proving this call site defers to the one centralized theme rather
      // than hardcoding a fill itself.
      expect(bg, isNull);
      expect(find.text('Host a Room'), findsOneWidget);
    });

    testWidgets('secondary/ghost/danger variants still render their '
        'existing Material button types', (tester) async {
      await tester.pumpWidget(
        wrap(
          Column(
            children: [
              HEButton(
                label: 'Join a Room',
                variant: HEButtonVariant.secondary,
                onPressed: () {},
              ),
              HEButton(
                label: 'Play vs AI',
                variant: HEButtonVariant.ghost,
                onPressed: () {},
              ),
              HEButton(
                label: 'Leave',
                variant: HEButtonVariant.danger,
                onPressed: () {},
              ),
            ],
          ),
        ),
      );

      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.byType(TextButton), findsNWidgets(2));
    });
  });

  group('HETextField — default style is unchanged', () {
    testWidgets(
      'renders a plain TextField relying on the app InputDecorationTheme',
      (tester) async {
        final controller = TextEditingController();
        await tester.pumpWidget(
          wrap(HETextField(controller: controller, hintText: 'Your name')),
        );

        final field = tester.widget<TextField>(find.byType(TextField));
        // Standard style leaves `decoration.filled`/`fillColor` unset,
        // deferring entirely to the ambient `InputDecorationTheme` — exactly
        // its pre-existing behavior, untouched by the Purple Floodlights
        // variant branch.
        expect(field.decoration?.filled, isNot(true));
        expect(field.decoration?.fillColor, isNull);
        expect(
          field.style,
          isNot(
            isA<TextStyle>().having((s) => s.color, 'color', HEColors.accent),
          ),
        );
      },
    );
  });

  group('HEButton — HEVisualStyle is now a no-op migration bridge', () {
    // Was: "purple style renders a distinctly different fill color without
    // altering the standard variant at another call site" — asserting
    // `standardBg` isNull and `purpleBg` isNotNull (i.e. the two styles
    // produced visibly different buttons). Retired by the Night Tactics
    // app-wide migration: HEButton collapsed its two rendering paths onto
    // one system, so `style` no longer changes anything. Updated to assert
    // the two now render IDENTICALLY (both defer to the same app theme),
    // proving the bridge is genuinely a no-op rather than silently reverted.
    testWidgets(
      'passing style: purpleFloodlights renders identically to the default',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            Column(
              children: [
                HEButton(label: 'Standard', onPressed: () {}),
                HEButton(
                  label: 'Purple',
                  onPressed: () {},
                  style: HEVisualStyle.purpleFloodlights,
                ),
              ],
            ),
          ),
        );

        final buttons = tester
            .widgetList<ElevatedButton>(find.byType(ElevatedButton))
            .toList();
        expect(buttons, hasLength(2));
        final standardBg = buttons[0].style?.backgroundColor?.resolve({});
        final purpleBg = buttons[1].style?.backgroundColor?.resolve({});
        // Both null — both defer to the one app-wide ElevatedButtonTheme.
        expect(standardBg, isNull);
        expect(purpleBg, isNull);
      },
    );
  });
}
