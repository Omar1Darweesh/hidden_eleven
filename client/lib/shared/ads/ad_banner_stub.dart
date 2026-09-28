import 'package:flutter/widgets.dart';

/// Non-web fallback — AdSense only serves on the web build.
Widget buildAdBannerElement({
  required String slotId,
  required double width,
  required double height,
}) {
  return const SizedBox.shrink();
}
