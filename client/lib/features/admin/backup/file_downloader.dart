// Conditionally-imported browser file save: `dart:html` isn't available
// outside web builds, so the real implementation is only pulled in when
// compiling for web; other platforms get a stub that throws.
export 'file_downloader_stub.dart'
    if (dart.library.html) 'file_downloader_web.dart';
