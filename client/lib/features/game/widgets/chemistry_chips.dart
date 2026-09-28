import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/models/user_chemistry_challenge.dart';

/// Compact chemistry chips for the Squad Preview.
///
/// ## Data-integrity contract
///
/// **Every value shown here is server-authored.** Each chip reads a real
/// [UserChemistryChallenge]'s own [UserChemistryChallenge.label],
/// [UserChemistryChallenge.reward], [UserChemistryChallenge.satisfied],
/// [UserChemistryChallenge.current] and [UserChemistryChallenge.required].
/// Nothing is computed, summed, approximated or invented here.
///
/// This is why the chips do **not** say things like "Club Core +6":
/// `ScoringPreview` exposes only `userChemTotal` and `cardChemTotal`, with no
/// per-category (club / nation / league) point breakdown. Producing a
/// category number would mean inventing it, so instead each chip surfaces one
/// real challenge — which is both honest and more useful, since the player
/// sees exactly which requirement is met and which is close.
///
/// [FitNoteCard] remains the detailed explanation surface; these chips are a
/// glanceable summary, not a replacement for it.
class ChemistryChips extends StatelessWidget {
  const ChemistryChips({
    super.key,
    required this.challenges,
    this.maxChips = 3,
  });

  final List<UserChemistryChallenge> challenges;

  /// Cap so the Squad Preview never fills with chips. Ranked selection below
  /// means the ones that survive the cap are the ones worth seeing.
  final int maxChips;

  /// Ranking, using only real data:
  ///   1. Satisfied challenges first — a met requirement is worth confirming.
  ///   2. Then by how close an unmet one is (current/required), so the
  ///      almost-there challenge surfaces ahead of an untouched one.
  ///   3. Then by reward, so a bigger prize breaks ties.
  List<UserChemistryChallenge> get _ranked {
    final list = List<UserChemistryChallenge>.from(challenges)
      ..sort((a, b) {
        if (a.satisfied != b.satisfied) return a.satisfied ? -1 : 1;
        if (!a.satisfied) {
          final pa = a.required == 0 ? 0.0 : a.current / a.required;
          final pb = b.required == 0 ? 0.0 : b.current / b.required;
          if (pa != pb) return pb.compareTo(pa);
        }
        return b.reward.compareTo(a.reward);
      });
    return list.take(maxChips).toList();
  }

  @override
  Widget build(BuildContext context) {
    // Omit entirely rather than showing an empty or approximated state.
    if (challenges.isEmpty) return const SizedBox.shrink();
    final ranked = _ranked;
    if (ranked.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [for (final c in ranked) _Chip(challenge: c)],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.challenge});

  final UserChemistryChallenge challenge;

  /// Progress is shown only when it is real and meaningful — an untouched
  /// challenge (0 of N) says "0/3", which is honest; a satisfied one shows
  /// its actual reward instead.
  String get _trailing => challenge.satisfied
      ? '+${challenge.reward}'
      : '${challenge.current}/${challenge.required}';

  @override
  Widget build(BuildContext context) {
    final met = challenge.satisfied;
    // Emerald means "actually satisfied" — a real status, per the Night
    // Tactics colour rule. Everything else stays lavender.
    final color = met ? HETheme.pfSuccess : HETheme.pfLavenderText;

    return Semantics(
      label: met
          ? '${challenge.label}, met, plus ${challenge.reward} points'
          : '${challenge.label}, ${challenge.current} of '
                '${challenge.required}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: met ? 0.13 : 0.07),
          borderRadius: BorderRadius.circular(HEShape.rPill),
          border: Border.all(color: color.withValues(alpha: met ? 0.45 : 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon as well as colour, so "met" survives greyscale.
            Icon(
              met ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
              size: 11,
              color: color,
            ),
            const SizedBox(width: 5),
            ConstrainedBox(
              // Server labels can be long; keep one chip from eating the row.
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                challenge.label,
                style: HETheme.body(
                  size: 11,
                  weight: FontWeight.w600,
                  color: met ? HETheme.pfTextPrimary : HETheme.pfTextSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _trailing,
              style: HETheme.mono(
                size: 10.5,
                weight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
