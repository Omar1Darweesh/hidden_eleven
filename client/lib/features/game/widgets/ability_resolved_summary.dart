import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/models/ability.dart';
import 'package:hidden_eleven/shared/widgets/he_button.dart';

/// Compact end-of-reveal summary: one row per ability that was actually
/// used (discards are silent by design — see backend `_revealAbilityActivations`,
/// which never logs a discard), plus a CTA to continue. Shown both inline at
/// the end of `AbilityRevealOverlay`'s sequence and safe to reuse anywhere
/// else the resolved log needs a compact read-out (e.g. a "what happened"
/// recap dialog later).
class AbilityResolvedSummary extends StatelessWidget {
  const AbilityResolvedSummary({
    super.key,
    required this.activations,
    required this.localPlayerId,
    required this.onContinue,
  });

  final List<AbilityActivation> activations;
  final String localPlayerId;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: HETheme.pfBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Abilities resolved',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: HETheme.pfTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            activations.isEmpty
                ? 'No one used their card this round.'
                : 'Here’s what happened, in order.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: HETheme.pfTextSecondary, fontSize: 12),
          ),
          if (activations.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final a in activations)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _summaryRow(a),
              ),
          ],
          const SizedBox(height: 6),
          HEButton(label: 'Edit final lineup', onPressed: onContinue),
        ],
      ),
    );
  }

  Widget _summaryRow(AbilityActivation a) {
    final meta = AbilityMeta.of(a.type);
    final isYou = a.byPlayerId == localPlayerId;
    // Any reason the ability did nothing — a stale target ("fizzled"), the
    // caster being frozen, or the target being protected — reads visually as
    // the same "this had no effect" state.
    final fizzled =
        a.summary.contains('fizzled') ||
        a.summary.contains('frozen') ||
        a.summary.contains('blocked by Protection');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: meta.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: meta.color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(meta.icon, color: meta.color, size: 17),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${isYou ? 'You' : a.byName} → ${meta.name}',
                  style: TextStyle(
                    color: meta.color,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  a.summary,
                  style: TextStyle(
                    color: fizzled
                        ? HETheme.pfTextMuted
                        : HETheme.pfTextSecondary,
                    fontSize: 11,
                    fontStyle: fizzled ? FontStyle.italic : FontStyle.normal,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
