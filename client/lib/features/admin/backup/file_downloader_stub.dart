import 'dart:typed_data';

/// Non-web fallback — the admin panel is web-primary, so a build targeting
/// another platform simply can't trigger a browser save.
void saveBytesAsFile(Uint8List bytes, String filename) {
  throw UnsupportedError('File download is only supported on Flutter web.');
}
