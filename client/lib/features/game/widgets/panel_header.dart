import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';


/// The one "icon chip + eyebrow label + headline" header pattern shared by
/// every phase panel that renders inside GameActionSheet (CandidatePanel,
/// HiddenPickPanel, SubsPanel, AbilityActivationPanel). Each of these used to
/// build its own near-identical header with slightly different spacing,
/// icon-chip sizing, and typography — this is the single version, so a
/// player sees the same "what panel is this / what do I do" shape no matter
/// which phase they're in.
class PanelHeader extends StatelessWidget {
  const PanelHeader({
    super.key,
    required this.icon,
    required this.eyebrow,
    required this.title,
    this.emphasized = true,
    this.color = HETheme.pfAccentViolet,
  });

  final IconData icon;

  /// Short all-caps label above the headline, e.g. "CHOOSE A PLAYER".
  final String eyebrow;

  /// The actual instruction/state sentence — the panel's short title, NOT a
  /// restatement of DraftStatusBar's instruction (that stays the single
  /// source of truth for "what do I do now").
  final String title;

  /// False for a passive/waiting state — dims the icon chip and headline to
  /// the neutral secondary color instead of [color].
  final bool emphasized;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final activeColor = emphasized ? color : HETheme.pfTextSecondary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: activeColor.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(child: Icon(icon, color: activeColor, size: 16)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: const TextStyle(
                  color: HETheme.pfTextSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: TextStyle(
                  color: activeColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
