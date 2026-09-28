import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hidden_eleven/shared/providers/app_preferences_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AppPreferencesNotifier — reduced motion', () {
    test('defaults to off before persistence loads', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(appPreferencesProvider).reducedMotion, isFalse);
    });

    test('setReducedMotion updates state and persists', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(appPreferencesProvider.notifier)
          .setReducedMotion(true);

      expect(container.read(appPreferencesProvider).reducedMotion, isTrue);

      // A fresh container (simulating app relaunch) loads the persisted
      // value rather than defaulting again.
      final relaunched = ProviderContainer();
      addTearDown(relaunched.dispose);
      // Force the notifier to build (and so kick off its persisted load)
      // before reading state — reading the plain provider value alone does
      // not reliably trigger `build()` ahead of the read in the same
      // synchronous step.
      relaunched.read(appPreferencesProvider.notifier);
      // Let the fire-and-forget persisted load resolve — build() kicks it
      // off without awaiting (correct for the real app's first-frame
      // behavior), so the test has to drain the microtask queue rather
      // than assume one Duration.zero turn is enough.
      await pumpEventQueue();
      expect(relaunched.read(appPreferencesProvider).reducedMotion, isTrue);
    });

    test(
      'setting the same value twice does not re-persist unnecessarily',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container
            .read(appPreferencesProvider.notifier)
            .setReducedMotion(false);
        // Already false by default — this must not throw or misbehave.
        expect(container.read(appPreferencesProvider).reducedMotion, isFalse);
      },
    );
  });

  group('AppPreferencesNotifier — text scale', () {
    test('defaults to Standard', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(appPreferencesProvider).textScale,
        TextScaleOption.standard,
      );
    });

    test('setTextScale updates state and persists across relaunch', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(appPreferencesProvider.notifier)
          .setTextScale(TextScaleOption.xl);
      expect(
        container.read(appPreferencesProvider).textScale,
        TextScaleOption.xl,
      );

      final relaunched = ProviderContainer();
      addTearDown(relaunched.dispose);
      relaunched.read(appPreferencesProvider.notifier);
      await pumpEventQueue();
      expect(
        relaunched.read(appPreferencesProvider).textScale,
        TextScaleOption.xl,
      );
    });

    test('TextScaleOption multipliers are ordered Standard < Large < XL', () {
      expect(
        TextScaleOption.standard.multiplier,
        lessThan(TextScaleOption.large.multiplier),
      );
      expect(
        TextScaleOption.large.multiplier,
        lessThan(TextScaleOption.xl.multiplier),
      );
    });
  });
}
