import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/shared/ads/ad_config.dart';
import 'package:hidden_eleven/shared/ads/interstitial_gate.dart';

/// Covers the interstitial frequency policy — the rules that keep ads from
/// making a fast rematch loop feel ad-heavy, and that protect a first-time
/// player's opening match from being interrupted.
void main() {
  final now = DateTime(2026, 8, 25, 12, 0, 0);

  group('InterstitialGate.shouldShow', () {
    test('never shows during the opening grace matches', () {
      for (var match = 1; match <= GameMonetizeConfig.graceMatches; match++) {
        expect(
          InterstitialGate.shouldShow(
            matchesFinished: match,
            lastShown: null,
            now: now,
            sdkReady: true,
          ),
          isFalse,
          reason: 'match $match falls inside the grace period',
        );
      }
    });

    test('shows on the first match past the grace period', () {
      expect(
        InterstitialGate.shouldShow(
          matchesFinished: GameMonetizeConfig.graceMatches + 1,
          lastShown: null,
          now: now,
          sdkReady: true,
        ),
        isTrue,
      );
    });

    test('suppresses a second ad inside the minimum interval', () {
      final justUnder = now.subtract(GameMonetizeConfig.minInterval ~/ 2);
      expect(
        InterstitialGate.shouldShow(
          matchesFinished: GameMonetizeConfig.graceMatches + 2,
          lastShown: justUnder,
          now: now,
          sdkReady: true,
        ),
        isFalse,
      );
    });

    test('allows another ad once the minimum interval has elapsed', () {
      final wellPast = now
          .subtract(GameMonetizeConfig.minInterval)
          .subtract(const Duration(seconds: 1));
      expect(
        InterstitialGate.shouldShow(
          matchesFinished: GameMonetizeConfig.graceMatches + 2,
          lastShown: wellPast,
          now: now,
          sdkReady: true,
        ),
        isTrue,
      );
    });

    test('shows nothing when the SDK never loaded', () {
      // Ad blocker, offline, or script error — must degrade silently rather
      // than blocking the result screen.
      expect(
        InterstitialGate.shouldShow(
          matchesFinished: GameMonetizeConfig.graceMatches + 1,
          lastShown: null,
          now: now,
          sdkReady: false,
        ),
        isFalse,
      );
    });
  });

  group('InterstitialGate.onMatchFinished', () {
    setUp(InterstitialGate.resetForTest);

    test(
      'is a no-op on non-web builds where the SDK stub reports not ready',
      () {
        // Guards the mobile/desktop path: the conditional import resolves to
        // gamemonetize_stub.dart here, so no ad is ever requested.
        expect(InterstitialGate.onMatchFinished(), isFalse);
        expect(InterstitialGate.onMatchFinished(), isFalse);
      },
    );
  });
}
