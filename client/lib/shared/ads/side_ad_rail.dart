import 'package:flutter/material.dart';
import 'package:hidden_eleven/shared/ads/ad_banner_widget.dart';
import 'package:hidden_eleven/shared/ads/ad_config.dart';

/// Wraps [child] with a fixed-size AdSense banner pinned to the right edge,
/// but only when the viewport is wide enough that the banner has genuine
/// open space beside the centered content — `ResponsiveLayout` caps content
/// at `kContentMaxWidth` (480px), so anything past ~1100px total width has
/// unused space on both sides. Never overlaps or competes with gameplay/UI
/// on narrow or mobile-web viewports, where this renders nothing extra.
class SideAdRail extends StatelessWidget {
  const SideAdRail({super.key, required this.slotId, required this.child});

  final String slotId;
  final Widget child;

  static const double _railWidth = 160;
  static const double _railHeight = 600;
  static const double _minViewportForRail = 1100;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final showRail = AdConfig.enabled && width >= _minViewportForRail;

    if (!showRail) return child;

    return Stack(
      children: [
        child,
        Positioned(
          right: 16,
          top: 16,
          child: AdBanner(
            slotId: slotId,
            width: _railWidth,
            height: _railHeight,
          ),
        ),
      ],
    );
  }
}
