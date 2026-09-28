/// Conditionally-imported AdSense `<ins>` embed: `dart:html`/`dart:ui_web`
/// aren't available outside web builds, mirroring the pattern in
/// features/admin/backup/file_downloader.dart.
export 'ad_banner_stub.dart' if (dart.library.html) 'ad_banner_web.dart';
