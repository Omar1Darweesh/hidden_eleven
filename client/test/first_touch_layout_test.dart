import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hidden_eleven/shared/widgets/first_touch_layout.dart';

void main() {
  Future<double> maxWidthAt(WidgetTester tester, Size size) async {
    // MaterialApp derives its own MediaQuery from the test binding's view
    // rather than an ancestor MediaQuery, so the viewport has to be set on
    // the view itself for FirstTouchLayout's `MediaQuery.sizeOf` read to see
    // the size this test actually wants.
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FirstTouchLayout(
            child: SizedBox(key: Key('probe'), width: 2000, height: 10),
          ),
        ),
      ),
    );
    return tester.getSize(find.byKey(const Key('probe'))).width;
  }

  testWidgets(
    'mobile width fills the viewport (minus 24px padding each side)',
    (tester) async {
      final w = await maxWidthAt(tester, const Size(390, 844));
      expect(w, 390 - 24 * 2);
    },
  );

  testWidgets('tablet width is capped narrower than desktop', (tester) async {
    final tablet = await maxWidthAt(tester, const Size(768, 1024));
    expect(tablet, 560);
  });

  testWidgets('desktop width gets the widest cap', (tester) async {
    final desktop = await maxWidthAt(tester, const Size(1920, 1080));
    expect(desktop, 680);
  });

  testWidgets('stays single-column: child keeps its own layout, no grid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FirstTouchLayout(
            child: Column(children: [Text('a'), Text('b')]),
          ),
        ),
      ),
    );
    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
  });
}
