import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/app/theme.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/services/chemistry_evaluator.dart';
import 'package:hidden_eleven/features/game/widgets/card_details_modal.dart';
import 'package:hidden_eleven/features/game/widgets/panel_header.dart';
import 'package:hidden_eleven/features/game/widgets/player_card.dart';
import 'package:hidden_eleven/shared/widgets/he_button.dart';
import 'package:hidden_eleven/shared/widgets/screen_entrance.dart';

// ── Candidate card selection panel ────────────────────────────────────────────

/// Displays a set of draft candidates for the active player to choose from.
///
/// Rendered as a fitted grid — enough columns (and, for larger candidate
/// counts, rows) to show every candidate at once with no scrolling, sized
/// down just enough to fit the available width. Draft rounds never offer
/// more than a handful of candidates at a time, so this comfortably fits
/// without cramming: ≤3 → single row, 4 → 2×2, 5-6 → 3 per row (2 rows),
/// 7+ → 4 per row (2 rows).
///
/// **Two-stage pick confirm** (dossier non-negotiable: no single-tap
/// irreversible draft pick). The first tap on a card only *stages* it —
/// [widget.onPick] (the real, wire-committing callback) is never invoked yet.
/// A confirm bar slides up naming the staged player; tapping it, or tapping
/// the same card again, commits. Tapping a *different* card re-stages
/// instead of committing, so changing your mind never accidentally locks in
/// the wrong player. This is presentation-only — `onPick`'s contract
/// (immediately sends `pick_card` over the socket) and every other caller
/// of [PlayerCard] are unchanged; the gate lives entirely here, the one real
/// call site that ever committed a pick.
class CandidatePanel extends StatefulWidget {
  const CandidatePanel({
    super.key,
    required this.candidates,
    required this.slotLabel,
    required this.slotBasePosition,
    required this.onPick,
    this.lineup = const [],
  });

  final List<CandidateCard> candidates;
  final String slotLabel;
  final String slotBasePosition;
  final ValueChanged<String> onPick;

  /// Current placed cards on the local player's pitch — used for chemistry evaluation.
  final List<LineupCard> lineup;

  @override
  State<CandidatePanel> createState() => _CandidatePanelState();
}

class _CandidatePanelState extends State<CandidatePanel> {
  static const double _minCardW = 88.0;
  static const double _cardGap = 8.0;

  String? _stagedCardId;

  static int _cols(int n, double availW) {
    final int maxCols = n <= 3
        ? n.clamp(1, 3)
        : n <= 6
        ? 3
        : 4;
    for (int c = maxCols; c >= 1; c--) {
      final cardW = (availW - _cardGap * (c - 1)) / c;
      if (cardW >= _minCardW) return c;
    }
    return 1;
  }

  /// The single entry point every pick path (grid tap, details-modal PICK
  /// button) now routes through. First touch on a card stages it; a second
  /// touch on the SAME card commits — `didUpdateWidget` below clears staging
  /// whenever the candidate pool itself changes (a new round), so a stale
  /// staged id can never carry over and auto-commit against a different set
  /// of candidates.
  void _handleTap(String cardId) {
    if (_stagedCardId == cardId) {
      _commit(cardId);
    } else {
      setState(() => _stagedCardId = cardId);
    }
  }

  void _commit(String cardId) {
    setState(() => _stagedCardId = null);
    widget.onPick(cardId);
  }

  void _cancelStaged() => setState(() => _stagedCardId = null);

  @override
  void didUpdateWidget(CandidatePanel old) {
    super.didUpdateWidget(old);
    if (old.candidates != widget.candidates) _stagedCardId = null;
  }

  // No outer bordered card here — this panel renders inside GameActionSheet,
  // which already supplies the one frame around whatever the current phase
  // needs. A second border/shadow around the content would just be a card
  // nested inside a card.
  @override
  Widget build(BuildContext context) {
    final stagedCard = widget.candidates
        .where((c) => c.cardId == _stagedCardId)
        .firstOrNull;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader(
          icon: Icons.person_add_rounded,
          eyebrow: 'CHOOSE A PLAYER',
          title: '${widget.slotLabel}  ·  ${widget.slotBasePosition}',
          color: HETheme.pfAccentViolet,
        ),
        const SizedBox(height: 12),
        widget.candidates.isEmpty
            ? const _EmptyState()
            : LayoutBuilder(
                builder: (ctx, box) {
                  final n = widget.candidates.length;
                  final availW = box.maxWidth;
                  final cols = _cols(n, availW);
                  final cardW = (availW - _cardGap * (cols - 1)) / cols;
                  // Identifies THIS round's specific pool — changes the
                  // instant a new round's candidates replace the old ones,
                  // which is exactly when the staggered entrance below
                  // should replay. Re-picking within the same round (a tap
                  // that only stages, never mutates `widget.candidates`)
                  // leaves this unchanged, so the cards never re-animate on
                  // a mere selection change.
                  final roundKey = widget.candidates
                      .map((c) => c.cardId)
                      .join('|');

                  return Wrap(
                    spacing: _cardGap,
                    runSpacing: _cardGap,
                    alignment: WrapAlignment.center,
                    children: widget.candidates.asMap().entries.map((entry) {
                      final i = entry.key;
                      final c = entry.value;
                      return SizedBox(
                        width: cardW,
                        // Height is derived from AspectRatio(3/4.2)
                        // inside PlayerCard — no explicit cardH needed.
                        child: ScreenEntrance(
                          key: ValueKey('$roundKey-${c.cardId}'),
                          duration: const Duration(milliseconds: 300),
                          delay: Duration(milliseconds: i * 60),
                          child: _StageableCandidate(
                            card: c,
                            isStaged: c.cardId == _stagedCardId,
                            onPick: () => _handleTap(c.cardId),
                            onTap: () => showCardDetailsModal(
                              ctx,
                              playerName: c.playerName,
                              rating: c.rating,
                              position: c.primaryPosition,
                              imageSeed: c.cardId,
                              club: c.club,
                              clubLogoUrl: c.clubLogoUrl,
                              primaryColor: c.primaryColor,
                              secondaryColor: c.secondaryColor,
                              tertiaryColor: c.tertiaryColor,
                              kitPattern: c.kitPattern,
                              cardStyle: c.cardStyle,
                              kitNumber: c.kitNumber,
                              nationality: c.nationality,
                              altPositions: c.naturalAltPositions,
                              pace: c.pace,
                              shooting: c.shooting,
                              passing: c.passing,
                              dribbling: c.dribbling,
                              defending: c.defending,
                              physical: c.physical,
                              chemistryBonuses: c.chemistryBonuses,
                              lineup: widget.lineup,
                              // The modal's own PICK button also only
                              // stages — closing back to the grid with the
                              // card staged and the confirm bar showing,
                              // never committing directly from the modal.
                              onPick: () {
                                Navigator.of(ctx).pop();
                                _handleTap(c.cardId);
                              },
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
        // ── Confirm bar ────────────────────────────────────────────────────
        // Slides in only once a card is staged; this is the one place a
        // pick actually commits from besides tapping the already-staged
        // card a second time.
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: stagedCard == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _ConfirmBar(
                    playerName: stagedCard.playerName,
                    onConfirm: () => _commit(stagedCard.cardId),
                    onCancel: _cancelStaged,
                  ),
                ),
        ),
      ],
    );
  }
}

// ── Staged-card presentation ───────────────────────────────────────────────

/// Wraps [PlayerCard] with the staged-selection glow — kept OUTSIDE
/// [PlayerCard] itself (whose public API stays untouched) since this is the
/// only call site that ever needs a "staged, awaiting confirm" visual.
class _StageableCandidate extends StatelessWidget {
  const _StageableCandidate({
    required this.card,
    required this.isStaged,
    required this.onPick,
    required this.onTap,
  });

  final CandidateCard card;
  final bool isStaged;
  final VoidCallback onPick;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(HERadius.md + 3),
        border: Border.all(
          color: isStaged ? HETheme.accentCyan : Colors.transparent,
          width: 2,
        ),
        boxShadow: isStaged
            ? [
                BoxShadow(
                  color: HETheme.accentCyan.withValues(alpha: 0.35),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.all(2),
      child: PlayerCard(card: card, onPick: onPick, onTap: onTap),
    );
  }
}

// ── Confirm bar ──────────────────────────────────────────────────────────────

class _ConfirmBar extends StatelessWidget {
  const _ConfirmBar({
    required this.playerName,
    required this.onConfirm,
    required this.onCancel,
  });

  final String playerName;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: HETheme.accentCyan.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(HERadius.md),
        border: Border.all(color: HETheme.accentCyan.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                style: HETheme.body(size: 13, color: HETheme.pfTextSecondary),
                children: [
                  const TextSpan(text: 'Confirm pick: '),
                  TextSpan(
                    text: playerName,
                    style: HETheme.body(
                      size: 13,
                      weight: FontWeight.w700,
                      color: HETheme.pfTextPrimary,
                    ),
                  ),
                  const TextSpan(text: '?'),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              semanticsLabel: 'Confirm pick: $playerName?',
            ),
          ),
          const SizedBox(width: 8),
          // 44x44 minimum touch target — small = false (52px height) is the
          // default HEButton size, which already clears it comfortably.
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              tooltip: 'Cancel',
              icon: const Icon(
                Icons.close_rounded,
                color: HETheme.pfTextSecondary,
              ),
              onPressed: onCancel,
            ),
          ),
          SizedBox(
            width: 140,
            child: HEButton(
              label: 'Confirm Pick',
              small: true,
              onPressed: onConfirm,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          'No candidates available',
          style: TextStyle(color: HETheme.pfTextSecondary, fontSize: 13),
        ),
      ),
    );
  }
}
