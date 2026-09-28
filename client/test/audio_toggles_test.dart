import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hidden_eleven/shared/audio/audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('sfxMutedProvider / musicMutedProvider — independence', () {
    test('each starts unmuted by default', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(sfxMutedProvider), isFalse);
      expect(container.read(musicMutedProvider), isFalse);
    });

    test('toggling sfx does not affect music, and vice versa', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(sfxMutedProvider.notifier).toggle();
      expect(container.read(sfxMutedProvider), isTrue);
      expect(
        container.read(musicMutedProvider),
        isFalse,
        reason: 'muting SFX must never mute music',
      );

      await container.read(musicMutedProvider.notifier).toggle();
      expect(container.read(musicMutedProvider), isTrue);
      expect(
        container.read(sfxMutedProvider),
        isTrue,
        reason: 'sfx mute set earlier must be unaffected by the music toggle',
      );
    });

    test('setValue is idempotent', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sfxMutedProvider.notifier).setValue(true);
      await container.read(sfxMutedProvider.notifier).setValue(true);
      expect(container.read(sfxMutedProvider), isTrue);
    });

    test('each flag persists independently across relaunch', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sfxMutedProvider.notifier).setValue(true);
      // Music deliberately left unmuted.

      final relaunched = ProviderContainer();
      addTearDown(relaunched.dispose);
      relaunched.read(sfxMutedProvider.notifier);
      relaunched.read(musicMutedProvider.notifier);
      await pumpEventQueue();

      expect(relaunched.read(sfxMutedProvider), isTrue);
      expect(relaunched.read(musicMutedProvider), isFalse);
    });
  });

  group('audioMutedProvider — combined "mute everything" view', () {
    test('reads muted only when BOTH flags are muted', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(audioMutedProvider), isFalse);

      await container.read(sfxMutedProvider.notifier).setValue(true);
      expect(
        container.read(audioMutedProvider),
        isFalse,
        reason: 'only one of two flags is muted so far',
      );

      await container.read(musicMutedProvider.notifier).setValue(true);
      expect(container.read(audioMutedProvider), isTrue);
    });

    testWidgets('toggleAllAudioMuted flips both flags together', (
      tester,
    ) async {
      late WidgetRef capturedRef;
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // toggleAllAudioMuted takes a WidgetRef, not a bare Ref/ProviderContainer
      // — a minimal Consumer is the real, non-mocked way to obtain one.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      await toggleAllAudioMuted(capturedRef);
      expect(container.read(sfxMutedProvider), isTrue);
      expect(container.read(musicMutedProvider), isTrue);
      expect(container.read(audioMutedProvider), isTrue);

      await toggleAllAudioMuted(capturedRef);
      expect(container.read(sfxMutedProvider), isFalse);
      expect(container.read(musicMutedProvider), isFalse);
      expect(container.read(audioMutedProvider), isFalse);
    });
  });
}
