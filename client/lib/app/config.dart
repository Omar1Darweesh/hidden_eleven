import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  // Explicit override wins. If omitted:
  //   • Web   → auto-derives ws://<same-host>:3000 from Uri.base (works for
  //             any device on the LAN that opens the web app by IP).
  //   • Other → falls back to ws://10.0.2.2:3000 (Android emulator default).
  // Override at build time: --dart-define=SOCKET_URL=ws://192.168.x.x:3000
  static const _configured = String.fromEnvironment(
    'SOCKET_URL',
    defaultValue: '',
  );

  static String get socketUrl {
    if (_configured.isNotEmpty) return _configured;
    if (kIsWeb) {
      // Derive from the page URL — works for localhost, LAN, and ngrok alike.
      // https://xxx.ngrok.io  → wss://xxx.ngrok.io
      // http://192.168.1.44:3000 → ws://192.168.1.44:3000
      final scheme = Uri.base.scheme == 'https' ? 'wss' : 'ws';
      final port =
          (Uri.base.port == 0 || Uri.base.port == 80 || Uri.base.port == 443)
          ? ''
          : ':${Uri.base.port}';
      return '$scheme://${Uri.base.host}$port';
    }
    return 'ws://10.0.2.2:3000';
  }

  static String get _httpBase {
    return socketUrl
        .replaceFirst('ws://', 'http://')
        .replaceFirst('wss://', 'https://');
  }

  /// Public server HTTP base (e.g. https://host or http://host:3000).
  static String get httpBase => _httpBase;

  /// Resolves a player/club/flag image URL:
  /// - null / empty → returns null (caller uses fallback)
  /// - relative path (e.g. /assets/...) → prefixes with server HTTP base
  /// - absolute external URL on web → routes through the server image proxy
  ///   so the browser avoids CORS restrictions from third-party CDNs
  /// - absolute external URL on native → returned as-is (no CORS on mobile)
  static String? resolveImageUrl(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (!raw.startsWith('http')) {
      // Relative path served by our server
      return '$_httpBase$raw';
    }
    if (kIsWeb) {
      // Route external URLs through proxy to avoid browser CORS blocks
      return '$_httpBase/api/admin/proxy/image?url=${Uri.encodeComponent(raw)}';
    }
    return raw;
  }
}
