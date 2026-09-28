import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';

/// Wraps a primary CTA button in a restrained colored glow — extracted from
/// the `Container(decoration: BoxDecoration(boxShadow: ...))` pattern
/// previously hand-repeated at each first-touch screen's main action.
///
/// [color] is the glow's semantic meaning, not a decorative choice — per the
/// app's color rules: cyan for the primary action (Host a Room, Join Room),
/// gold reserved for hidden/classified/reveal-adjacent moments only.
class PrimaryCtaGlow extends StatelessWidget {
  const PrimaryCtaGlow({
    super.key,
    required this.child,
    this.color = HETheme.pfAccentViolet,
    this.intensity = 0.18,
  });

  final Widget child;
  final Color color;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(HETheme.radiusMd),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: intensity),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
