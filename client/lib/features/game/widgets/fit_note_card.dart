import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';

import 'package:hidden_eleven/features/game/models/chemistry_bonus.dart';
import 'package:hidden_eleven/features/game/services/chemistry_evaluator.dart';

/// Plain-language chemistry explanation — the dossier's "Fit Notes" panel.
///
/// **Data integrity contract:** every number and every sentence here comes
/// straight from server-authored data. [ChemistryBonus.label] is the
/// server's own plain-English description of the rule; [ChemistryBonus.reward]
/// is the server's own point value. This widget decides only two things
/// itself, both already-audited client mirrors used elsewhere in this
/// codebase (`card_details_modal.dart`'s `_ChemistrySection`,
/// `result_screen.dart`'s `_CardChemDetailCard`): whether a challenge is
/// currently satisfied ([ChemistryEvaluator.isSatisfied], which the
/// evaluator's own doc comment states mirrors `scoring.ts` exactly) and how
/// close an unmet one is ([ChemistryEvaluator.progressOf]). No score is
/// computed or recomputed here — this widget only ranks and phrases
/// already-existing values.
class FitNoteCard extends StatelessWidget {
  const FitNoteCard({
    super.key,
    required this.bonuses,
    required this.lineup,
    this.ownerClub,
    this.isLoading = false,
  });

  final List<ChemistryBonus> bonuses;
  final List<LineupCard> lineup;

  /// Club of the card these bonuses belong to — Icons/Heroes are exempt
  /// (every challenge counts as satisfied), matching
  /// `ChemistryEvaluator.activeSlotIndices`'s own exemption handling exactly
  /// so this panel can never show a different verdict than the badge next
  /// to the card.
  final String? ownerClub;

  /// Set by a caller whose OWN bonus/lineup data hasn't arrived yet (this
  /// widget's own inputs are always synchronous once provided — there is no
  /// internal async step — so this exists for a future caller's benefit,
  /// not because this widget fetches anything itself).
  final bool isLoading;

  bool get _isExempt =>
      ownerClub != null && chemistryExemptClubs.contains(ownerClub);

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const _FitNoteSkeleton();
    if (bonuses.isEmpty) return const _FitNoteEmpty();

    final notes = _rankedNotes();

    return Semantics(
      container: true,
      label:
          'Tactical fit: ${notes.where((n) => n.satisfied).length} of '
          '${notes.length} challenges met',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < notes.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _FitNoteRow(note: notes[i]),
          ],
        ],
      ),
    );
  }

  /// Satisfied challenges first (highest reward first — the strongest
  /// factors), then unmet ones ordered by how close they are to completion,
  /// so a nearly-there challenge reads before a distant one.
  List<_RankedNote> _rankedNotes() {
    final notes = bonuses.map((bonus) {
      final satisfied =
          _isExempt || ChemistryEvaluator.isSatisfied(bonus, lineup);
      final progress = ChemistryEvaluator.progressOf(bonus, lineup);
      return _RankedNote(
        bonus: bonus,
        satisfied: satisfied,
        progress: progress,
      );
    }).toList();

    notes.sort((a, b) {
      if (a.satisfied != b.satisfied) {
        return a.satisfied ? -1 : 1;
      }
      if (a.satisfied) {
        // Both satisfied: higher reward (the stronger factor) first.
        return b.bonus.reward.compareTo(a.bonus.reward);
      }
      // Both unmet: closer to completion first.
      final aFrac = a.progress.required == 0
          ? 0.0
          : a.progress.current / a.progress.required;
      final bFrac = b.progress.required == 0
          ? 0.0
          : b.progress.current / b.progress.required;
      return bFrac.compareTo(aFrac);
    });

    return notes;
  }
}

class _RankedNote {
  const _RankedNote({
    required this.bonus,
    required this.satisfied,
    required this.progress,
  });

  final ChemistryBonus bonus;
  final bool satisfied;
  final ({int current, int required}) progress;
}

class _FitNoteRow extends StatelessWidget {
  const _FitNoteRow({required this.note});
  final _RankedNote note;

  @override
  Widget build(BuildContext context) {
    final satisfied = note.satisfied;
    // Distinguishable without color alone: a filled check vs. an outlined
    // circle, not just a color swap — colorblind-safe per the dossier's
    // accessibility rule, and consistent with the check/outline convention
    // `_SBreakdownRow` (result_screen.dart) already uses for the same
    // satisfied/unmet distinction.
    final icon = satisfied
        ? Icons.check_circle_rounded
        : Icons.radio_button_unchecked_rounded;
    final color = satisfied ? HETheme.accentEmerald : HETheme.pfTextSecondary;

    final statusPhrase = satisfied
        ? 'Met'
        : 'Not yet met, ${note.progress.current} of ${note.progress.required}';

    return Semantics(
      label:
          '${note.bonus.label}. $statusPhrase. Worth ${note.bonus.reward} points.',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // Server-authored plain-language description — not
                  // synthesized here, so this can never say something the
                  // scoring rule doesn't actually mean.
                  note.bonus.label,
                  style: HETheme.body(
                    size: 13,
                    weight: FontWeight.w600,
                    color: satisfied
                        ? HETheme.pfTextPrimary
                        : HETheme.pfTextSecondary,
                  ),
                ),
                if (!satisfied) ...[
                  const SizedBox(height: 3),
                  Text(
                    '${note.progress.current} of ${note.progress.required} so far',
                    style: HETheme.body(size: 11.5, color: HETheme.pfTextMuted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '+${note.bonus.reward}',
            style: HETheme.mono(
              size: 12.5,
              weight: FontWeight.w800,
              color: satisfied ? HETheme.accentEmerald : HETheme.pfTextMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _FitNoteEmpty extends StatelessWidget {
  const _FitNoteEmpty();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'No chemistry challenges on this card',
      child: Text(
        'No chemistry challenges on this card.',
        style: HETheme.body(size: 12.5, color: HETheme.pfTextMuted),
      ),
    );
  }
}

class _FitNoteSkeleton extends StatelessWidget {
  const _FitNoteSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width) => Container(
      height: 12,
      width: width,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: HETheme.surfaceRaised,
        borderRadius: BorderRadius.circular(4),
      ),
    );
    return Semantics(
      label: 'Loading tactical fit',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [bar(double.infinity), bar(160), bar(200)],
      ),
    );
  }
}
