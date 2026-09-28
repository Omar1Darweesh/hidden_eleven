import 'package:flutter/material.dart';
import 'package:hidden_eleven/shared/ads/ad_banner.dart';
import 'package:hidden_eleven/shared/ads/ad_config.dart';

/// A fixed-size AdSense banner. Renders nothing while [AdConfig.enabled] is
/// false (no real client/slot IDs configured yet) — safe to leave wired
/// into every screen ahead of AdSense approval.
class AdBanner extends StatelessWidget {
  const AdBanner({
    super.key,
    required this.slotId,
    this.width = 300,
    this.height = 600,
  });

  final String slotId;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (!AdConfig.enabled) return const SizedBox.shrink();
    return SizedBox(
      width: width,
      height: height,
      child: buildAdBannerElement(slotId: slotId, width: width, height: height),
    );
  }
}
