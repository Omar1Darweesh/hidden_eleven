import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/theme.dart';

/// The Hidden Eleven brand mark — the crest+wordmark logo asset framed as a
/// premium badge: a soft cool-white plate (the logo's own artwork is a flat
/// JPG on white, so this treats that as a deliberate light "badge" rather
/// than cropping/recolouring the source image) with a cyan-tinted border and
/// a soft glow halo, matching the logo's own navy/cyan crest colours.
///
/// Reusable anywhere the brand needs to appear at full strength — home hero,
/// splash, login — not just this page. Use [compact] for smaller header/nav
/// contexts where the glow would be excessive.
class HELogoMark extends StatelessWidget {
  const HELogoMark({super.key, this.height = 168, this.compact = false});

  final double height;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Hidden Eleven',
      image: true,
      child: Container(
        padding: EdgeInsets.all(compact ? 8 : 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F7FB),
          borderRadius: BorderRadius.circular(
            compact ? HERadius.md : HERadius.xl,
          ),
          border: Border.all(
            color: HEColors.brandCyan.withValues(alpha: 0.45),
            width: compact ? 1 : 1.5,
          ),
          boxShadow: compact ? null : HEShadows.cyan(intensity: 0.30, blur: 36),
        ),
        child: Image.asset(
          'assets/branding/hidden_11_logo.jpg',
          height: height,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
