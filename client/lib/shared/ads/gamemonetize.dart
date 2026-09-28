/// Conditionally-imported GameMonetize SDK bridge: `dart:js` isn't available
/// outside web builds, mirroring the pattern in ads/ad_banner.dart and
/// features/admin/backup/file_downloader.dart.
library;

export 'gamemonetize_stub.dart' if (dart.library.html) 'gamemonetize_web.dart';
