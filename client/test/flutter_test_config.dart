import 'dart:async';

import 'package:hidden_eleven/shared/widgets/event_atmosphere_background.dart';

/// Runs once before the whole widget-test suite.
///
/// The Tournament/Results atmosphere drifts on a permanently repeating
/// ambient controller. That is correct for real users, but it means
/// `pumpAndSettle()` can never settle on any screen showing it — every
/// existing test of those screens would hang rather than fail cleanly.
///
/// Turning the drift off suite-wide keeps those tests asserting the settled
/// composition (which is what they actually care about), while the drift
/// itself is covered explicitly by `event_atmosphere_background_test.dart`,
/// which re-enables it for the cases that assert the clock's behaviour.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  EventAtmosphereBackground.debugAmbientDriftEnabled = false;
  await testMain();
}
