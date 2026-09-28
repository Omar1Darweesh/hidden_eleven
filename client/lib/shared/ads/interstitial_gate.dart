import 'package:hidden_eleven/shared/ads/ad_config.dart';
import 'package:hidden_eleven/shared/ads/gamemonetize.dart';

/// Decides *whether* an interstitial should run, keeping that policy in one
/// place instead of scattering timing rules through screen widgets.
///
/// State is per-session and deliberately in-memory: a page reload resets the
/// grace period, which is the forgiving direction to err in. Persisting a
/// "matches played" counter across reloads would mean a returning player is
/// eligible for an ad the instant they arrive.
abstract final class InterstitialGate {
  static int _matchesFinished = 0;
  static DateTime? _lastShown;

  /// Pure policy, split out from [onMatchFinished] so it can be tested on the
  /// Dart VM — where the SDK bridge is the non-web stub and would otherwise
  /// force every decision to `false`, making the caps untestable.
  ///
  /// [matchesFinished] counts the match that just ended (so the first match
  /// of a session arrives here as 1).
  static bool shouldShow({
    required int matchesFinished,
    required DateTime? lastShown,
    required DateTime now,
    required bool sdkReady,
  }) {
    if (!GameMonetizeConfig.enabled) return false;
    if (matchesFinished <= GameMonetizeConfig.graceMatches) return false;
    if (!sdkReady) return false;
    if (lastShown != null &&
        now.difference(lastShown) < GameMonetizeConfig.minInterval) {
      return false;
    }
    return true;
  }

  /// Call once per finished match, from the screen that marks a match over.
  /// Returns true if an ad was actually requested, so callers can log or
  /// adapt UI; most call sites can ignore the result.
  static bool onMatchFinished() {
    _matchesFinished++;
    final now = DateTime.now();

    final show = shouldShow(
      matchesFinished: _matchesFinished,
      lastShown: _lastShown,
      now: now,
      sdkReady: isGameMonetizeReady,
    );
    if (!show) return false;

    _lastShown = now;
    showGameMonetizeInterstitial();
    return true;
  }

  /// Test hook — resets session state so cap behaviour can be asserted
  /// deterministically.
  static void resetForTest() {
    _matchesFinished = 0;
    _lastShown = null;
  }
}
