import 'dart:html' as html;
import 'dart:typed_data';

/// Triggers a browser "Save As" for [bytes] using an in-memory object URL —
/// no server round trip beyond the initial fetch, and nothing touches disk
/// until the browser writes the download itself.
void saveBytesAsFile(Uint8List bytes, String filename) {
  final url = html.Url.createObjectUrlFromBlob(html.Blob([bytes]));
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
