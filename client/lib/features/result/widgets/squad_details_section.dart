import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/app/theme.dart' show HERadius;

/// Wraps the squad/chemistry detail content (line stats, per-card chemistry,
/// the pitch view) so it's collapsed by default — useful information that
/// shouldn't dominate the page or compete with the winner/points/awards
/// sections above it. Built on the stock `ExpansionTile` (no new dependency).
class SquadDetailsSection extends StatelessWidget {
  final String subtitle;
  final Widget child;

  const SquadDetailsSection({
    super.key,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(HERadius.lg),
      side: const BorderSide(color: HETheme.pfBorder),
    );
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        backgroundColor: HETheme.pfSurfaceRaised,
        collapsedBackgroundColor: HETheme.pfSurfaceRaised,
        shape: shape,
        collapsedShape: shape,
        iconColor: HETheme.pfAccentViolet,
        collapsedIconColor: HETheme.pfTextSecondary,
        title: const Text(
          'SQUAD & CHEMISTRY DETAILS',
          style: TextStyle(
            color: HETheme.pfTextPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            color: HETheme.pfTextSecondary,
            fontSize: 11,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: child,
          ),
        ],
      ),
    );
  }
}
