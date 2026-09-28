/// Google AdSense configuration. `enabled` is deliberately false until a
/// real client ID and slot IDs are filled in below — every ad widget renders
/// nothing (not a broken/blank box) while this is false, so the app is safe
/// to ship before the AdSense application for hiddeneleven.online is
/// approved. See web/index.html for the matching adsbygoogle.js script tag,
/// which also needs its ADSENSE_CLIENT_ID placeholder replaced at the same
/// time as this file.
abstract final class AdConfig {
  /// Flip to true once AdSense approval is granted and every slot ID below
  /// is replaced with a real one from the AdSense dashboard.
  static const bool enabled = false;

  /// Same value as web/index.html's adsbygoogle.js script tag.
  static const String clientId = 'ca-pub-5635881358498755';

  static const String homeSideSlot = 'REPLACE_HOME_SIDE_SLOT_ID';
  static const String lobbySideSlot = 'REPLACE_LOBBY_SIDE_SLOT_ID';
  static const String gameSideSlot = 'REPLACE_GAME_SIDE_SLOT_ID';
}

/// GameMonetize configuration — a second, independent ad network from
/// AdConfig above. Unlike AdSense (which renders `<ins>` banners into the
/// page), GameMonetize serves a full-screen video/interstitial on demand via
/// its own SDK, so it needs no slot IDs and no layout space; the only
/// integration points are the loader in web/index.html and the
/// `showInterstitial()` call sites.
///
/// hiddeneleven.online is already an approved GameMonetize publisher domain
/// and carries their ads.txt lines, so this is enabled — approval alone
/// serves nothing, the SDK call below is what actually shows an ad.
abstract final class GameMonetizeConfig {
  static const bool enabled = true;

  /// Unique game identifier from the GameMonetize dashboard
  /// (Developer → My Games → Hidden Eleven). Must match the `gameId` passed
  /// to `window.SDK_OPTIONS` in web/index.html — the SDK reports ad
  /// impressions against this ID, so a mismatch means unattributed revenue.
  static const String gameId = 'dtjt1o329c7aw89m73lr4328zdgcdzmy';

  /// Shortest gap between two interstitials in a single session. The SDK
  /// enforces its own midroll timer server-side, but a local floor keeps a
  /// fast rematch loop from feeling ad-heavy even if that timer is lenient.
  static const Duration minInterval = Duration(minutes: 4);

  /// Matches finished before the first interstitial is allowed. A player who
  /// just discovered the game should see one complete match end-to-end
  /// without an ad break; monetising the very first result screen is the
  /// fastest way to lose a first-time visitor.
  static const int graceMatches = 1;
}
