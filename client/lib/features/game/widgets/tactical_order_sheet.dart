import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_motion.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/game_provider.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/widgets/card_details_modal.dart';

/// The "Tactical Order" sheet — where the first player sets the priority of
/// the remaining cards before rivals pick blind.
///
/// Extracted from `game_screen.dart`'s private `_OrderDeckDialog` and
/// restyled to Night Tactics. **All reorder behaviour is preserved exactly**:
/// same `ReorderableListView`, same index arithmetic, same
/// `ReorderableDragStartListener` (so keyboard and assistive-tech reordering
/// keep working), same `_confirming` latch, same `cardId` list sent to
/// `orderHiddenDeck`.
///
/// The one real behavioural fix: the previous implementation passed
/// `proxyDecorator: (child, index, animation) => child`, which explicitly
/// threw away Flutter's default drag lift. Dragging therefore had no
/// feedback at all — the row simply teleported. [_liftedProxy] restores it
/// deliberately, with a Night Tactics treatment rather than Material's
/// default grey elevation.
class TacticalOrderSheet extends StatefulWidget {
  const TacticalOrderSheet({
    super.key,
    required this.prompt,
    required this.onConfirm,
  });

  final FirstPlayerOrderData prompt;
  final ValueChanged<List<String>> onConfirm;

  @override
  State<TacticalOrderSheet> createState() => _TacticalOrderSheetState();
}

class _TacticalOrderSheetState extends State<TacticalOrderSheet> {
  late List<CandidateCard> _ordered;
  bool _confirming = false;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _ordered = List.of(widget.prompt.cards);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = HEMotion.reduced(context);
  }

  void _confirm() {
    // Confirm is never gated behind an animation.
    if (_confirming) return;
    setState(() => _confirming = true);
    widget.onConfirm(_ordered.map((c) => c.cardId).toList());
  }

  /// The dragged row, lifted above the list.
  ///
  /// Under reduced motion the lift is skipped entirely — the row keeps its
  /// resting appearance and only the reorder itself happens, per the
  /// "no travel/lift, but rank updates stay understandable" rule.
  Widget _liftedProxy(Widget child, int index, Animation<double> animation) {
    if (_reduced) return child;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        // Curves.easeOut over the drag-start animation: a quick, small lift
        // rather than a bounce.
        final t = Curves.easeOut.transform(animation.value);
        return Transform.scale(
          scale: 1 + 0.03 * t,
          child: Material(
            color: Colors.transparent,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(HEShape.rMd),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45 * t),
                    blurRadius: 24 * t,
                    offset: Offset(0, 8 * t),
                  ),
                  BoxShadow(
                    color: HETheme.pfAccentViolet.withValues(alpha: 0.35 * t),
                    blurRadius: 26 * t,
                    spreadRadius: -6,
                  ),
                ],
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: DecoratedBox(
          decoration: HEElevation.e2(radius: HEShape.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Brief(),
              Flexible(
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                  itemCount: _ordered.length,
                  proxyDecorator: _liftedProxy,
                  onReorder: (oldIndex, newIndex) {
                    // Index arithmetic preserved verbatim.
                    setState(() {
                      if (newIndex > oldIndex) newIndex--;
                      final card = _ordered.removeAt(oldIndex);
                      _ordered.insert(newIndex, card);
                    });
                  },
                  itemBuilder: (context, i) => _OrderRow(
                    key: ValueKey(_ordered[i].cardId),
                    card: _ordered[i],
                    rank: i + 1,
                    index: i,
                    reduced: _reduced,
                  ),
                ),
              ),
              _Actions(
                confirming: _confirming,
                onShuffle: _confirming
                    ? null
                    : () => setState(() => _ordered.shuffle()),
                onConfirm: _confirming ? null : _confirm,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mission-briefing header — replaces the stock dialog title row.
class _Brief extends StatelessWidget {
  const _Brief();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: HETheme.pfGold.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(HEShape.rPill),
              border: Border.all(color: HETheme.pfGold.withValues(alpha: 0.4)),
            ),
            child: Text(
              'YOUR CALL',
              style: HETheme.mono(
                size: 9.5,
                weight: FontWeight.w800,
                color: HETheme.pfGold,
              ).copyWith(letterSpacing: 1.3),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Set your priority',
            style: HETheme.body(
              size: 21,
              weight: FontWeight.w700,
              color: HETheme.pfTextPrimary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'You choose the order. Rivals pick blind.',
            style: HETheme.body(size: 13.5, color: HETheme.pfTextSecondary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.drag_indicator_rounded,
                size: 14,
                color: HETheme.pfTextMuted,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'Drag a dossier by its handle to move it up or down.',
                  style: HETheme.body(size: 11.5, color: HETheme.pfTextMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One priority row — a mini dossier rather than a flat list item.
class _OrderRow extends StatelessWidget {
  const _OrderRow({
    super.key,
    required this.card,
    required this.rank,
    required this.index,
    required this.reduced,
  });

  final CandidateCard card;
  final int rank;
  final int index;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final tier = CardTier.forCard(card.rating, card.cardStyle);

    return Semantics(
      label: '${card.playerName}, priority $rank of the deck',
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: HETheme.pfSurfaceRaised.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(HEShape.rMd),
          border: Border.all(color: HETheme.pfBorder),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(HEShape.rMd),
          child: Row(
            children: [
              // Tier as a left rail rather than a full border — quieter, and
              // it stops every row reading as an outlined box.
              Container(width: 3, height: 62, color: tier.accentColor),
              ReorderableDragStartListener(
                index: index,
                child: SizedBox(
                  // 44px minimum drag target.
                  width: 44,
                  height: 62,
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    color: HETheme.pfTextMuted,
                    size: 20,
                  ),
                ),
              ),
              _RankMedallion(rank: rank, reduced: reduced),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      card.playerName,
                      style: HETheme.body(
                        size: 13.5,
                        weight: FontWeight.w700,
                        color: HETheme.pfTextPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (card.nationality != null) ...[
                          FlagWidget(nationality: card.nationality!, size: 13),
                          const SizedBox(width: 6),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: HETheme.pfSurfaceGlass.withValues(
                              alpha: 0.7,
                            ),
                            borderRadius: BorderRadius.circular(HEShape.rPill),
                          ),
                          child: Text(
                            card.basePositionType,
                            style: HETheme.mono(
                              size: 9.5,
                              weight: FontWeight.w700,
                              color: HETheme.pfLavenderText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  '${card.rating}',
                  style: HETheme.mono(
                    size: 18,
                    weight: FontWeight.w800,
                    color: tier.accentColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The priority number, as a hexagonal medallion whose digit rolls when the
/// rank changes — so a reorder is legible without watching the whole list.
class _RankMedallion extends StatelessWidget {
  const _RankMedallion({required this.rank, required this.reduced});

  final int rank;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final digit = Text(
      '$rank',
      key: ValueKey(rank),
      style: HETheme.mono(
        size: 12.5,
        weight: FontWeight.w800,
        color: HETheme.pfLavenderText,
      ),
    );

    return SizedBox(
      width: 30,
      height: 30,
      child: CustomPaint(
        painter: const _HexPainter(),
        child: Center(
          child: reduced
              // Reduced motion: the number still updates, it just doesn't
              // travel. Rank changes stay understandable.
              ? digit
              : AnimatedSwitcher(
                  duration: HEMotion.confirm,
                  transitionBuilder: (child, anim) => SlideTransition(
                    position: Tween(
                      begin: const Offset(0, 0.5),
                      end: Offset.zero,
                    ).animate(anim),
                    child: FadeTransition(opacity: anim, child: child),
                  ),
                  child: digit,
                ),
        ),
      ),
    );
  }
}

class _HexPainter extends CustomPainter {
  const _HexPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Flat-top hexagon.
    final path = Path()
      ..moveTo(w * 0.25, h * 0.06)
      ..lineTo(w * 0.75, h * 0.06)
      ..lineTo(w * 0.98, h * 0.5)
      ..lineTo(w * 0.75, h * 0.94)
      ..lineTo(w * 0.25, h * 0.94)
      ..lineTo(w * 0.02, h * 0.5)
      ..close();

    canvas.drawPath(
      path,
      Paint()..color = HETheme.pfAccentViolet.withValues(alpha: 0.18),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = HETheme.pfAccentViolet.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(_HexPainter oldDelegate) => false;
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.confirming,
    required this.onShuffle,
    required this.onConfirm,
  });

  final bool confirming;
  final VoidCallback? onShuffle;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Row(
        children: [
          // Secondary — outlined, lavender. Never competes with Confirm.
          OutlinedButton.icon(
            onPressed: onShuffle,
            icon: const Icon(Icons.shuffle_rounded, size: 16),
            label: const Text('Shuffle'),
            style: OutlinedButton.styleFrom(
              foregroundColor: HETheme.pfLavenderText,
              side: BorderSide(
                color: HETheme.pfSecondaryViolet.withValues(alpha: 0.7),
              ),
              minimumSize: const Size(0, 46),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(HEShape.rPill),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Primary — violet, per the Night Tactics rule that emerald means
          // success/ready and is not a brand colour for CTAs.
          Expanded(
            child: FilledButton.icon(
              onPressed: onConfirm,
              icon: confirming
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    )
                  : const Icon(Icons.check_rounded, size: 17),
              label: Text(confirming ? 'Sending…' : 'Confirm order'),
              style: FilledButton.styleFrom(
                backgroundColor: HETheme.pfAccentViolet,
                foregroundColor: Colors.white,
                disabledBackgroundColor: HETheme.pfSecondaryViolet.withValues(
                  alpha: 0.55,
                ),
                minimumSize: const Size(0, 46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(HEShape.rPill),
                ),
                textStyle: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
