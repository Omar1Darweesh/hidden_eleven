/// Non-web fallback — the GameMonetize SDK is a browser-only JavaScript
/// library, so on mobile/desktop builds every entry point is a no-op and
/// callers need no platform checks of their own.
void showGameMonetizeInterstitial() {}

bool get isGameMonetizeReady => false;
