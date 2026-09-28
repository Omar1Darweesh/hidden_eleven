import 'dart:js' as js;

/// Web bridge to the GameMonetize HTML5 SDK loaded in web/index.html.
///
/// The SDK exposes itself as the global `window.sdk` once it has finished
/// initialising, and `showBanner()` is its interstitial call — the name is a
/// historical artefact of the SDK's API, not a small inline banner. It
/// renders a full-screen video/display ad over the page and fires
/// `SDK_GAME_PAUSE` / `SDK_GAME_START` around it (wired up in index.html).

/// True once `window.sdk` exists. The SDK is injected after `window.load`
/// and initialises asynchronously, so this is false for the first moments of
/// a session and callers must tolerate that rather than assuming readiness.
bool get isGameMonetizeReady {
  try {
    return js.context['sdk'] != null;
  } catch (_) {
    return false;
  }
}

/// Requests one interstitial. Safe to call unconditionally: if the SDK never
/// loaded (ad blocker, offline, script error) or is still initialising, this
/// returns silently instead of throwing into the widget tree that called it.
///
/// Frequency capping is the caller's job — see GameMonetizeConfig and
/// InterstitialGate; this function always asks the SDK when invoked.
void showGameMonetizeInterstitial() {
  try {
    final sdk = js.context['sdk'];
    if (sdk == null) return;
    sdk.callMethod('showBanner');
  } catch (_) {
    // Never let an ad-network failure surface as a crash in gameplay UI.
  }
}
