import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/theme.dart';

/// Provider attribution mark — credits OYO as the studio behind Hidden
/// Eleven. Shown under the brand hero on the home screen ("splash") and
/// reusable anywhere the provider needs to be surfaced.
///
/// The source artwork (assets/branding/OYO.png) is a wordmark centred on a
/// large navy field, so this frames it as a deliberate rounded badge whose
/// fill matches that navy, and uses BoxFit.cover in a wide box to crop the
/// excess vertical padding so the "OYO" wordmark reads at a legible size
/// rather than shrinking to a few pixels inside the square source.
class ProviderCredit extends StatelessWidget {
  const ProviderCredit({super.key, this.logoWidth = 132, this.logoHeight = 44});

  final double logoWidth;
  final double logoHeight;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'A game by OYO',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'A GAME BY',
            style: TextStyle(
              color: HEColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.4,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0B1E3D),
              borderRadius: BorderRadius.circular(HERadius.md),
              border: Border.all(
                color: HEColors.brandCyan.withValues(alpha: 0.22),
                width: 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: logoWidth,
              height: logoHeight,
              child: Image.asset(
                'assets/branding/OYO.png',
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                // Cap the decoded bitmap so this small badge never holds a
                // full-resolution decode in memory (the source is already
                // downscaled to 384², this keeps the decode cheaper still).
                cacheWidth: 320,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
