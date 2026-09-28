import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_motion.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';

/// The one docked-bottom zone in the narrow (mobile) game layout — whatever
/// the current phase needs the player to do or see lives here, in a single
/// consistent frame, instead of each phase panel sitting bare in a scrolling
/// column stacked below the pitch.
///
/// Two height states rather than one fixed cap: [compactMaxHeight] is the
/// default (content taller than it scrolls internally, same as before), and
/// [expandedMaxHeight] is reachable via the drag-handle control below for
/// content that genuinely needs more room — a longer candidate list, or the
/// same content at a larger text-size setting. The pitch stage above this
/// sheet is always `Expanded` in the caller's layout, so it keeps whatever
/// space remains in either state; [expandedMaxHeight] is itself capped by
/// the caller well short of the full viewport specifically so the pitch is
/// never reduced to nothing even at maximum expansion.
///
/// This is the ONE frame for whatever phase content it holds — CandidatePanel,
/// HiddenPickPanel, SubsPanel, etc. no longer carry their own bordered card
/// (that would just be a card nested inside this one), so this container is
/// what gives the docked zone its visual identity: a slightly elevated
/// surface tint + a top divider, not a heavy bordered box. An optional short
/// [title] exists for the rare panel that doesn't already self-title via
/// PanelHeader — passing one when the child already has its own heading
/// would just be the same duplicated-instruction problem Phase 1 removed.
class GameActionSheet extends StatefulWidget {
  const GameActionSheet({
    super.key,
    required this.child,
    required this.compactMaxHeight,
    required this.expandedMaxHeight,
    this.title,
  });

  final Widget child;
  final double compactMaxHeight;
  final double expandedMaxHeight;
  final String? title;

  @override
  State<GameActionSheet> createState() => _GameActionSheetState();
}

class _GameActionSheetState extends State<GameActionSheet> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final maxHeight = _expanded
        ? widget.expandedMaxHeight
        : widget.compactMaxHeight;

    return SafeArea(
      top: false,
      child: AnimatedContainer(
        duration: HEMotion.drawer,
        curve: HEMotion.easeOut,
        constraints: BoxConstraints(maxHeight: maxHeight),
        // Night Tactics: a floating glass drawer rather than a flat surface
        // with a hairline top border. Rounded on all four corners (not just
        // the top) because it now floats over the arena instead of being
        // welded to the screen edge.
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              HETheme.pfSurfaceGlass.withValues(alpha: 0.72),
              HETheme.pfSurfaceRaised.withValues(alpha: 0.62),
            ],
          ),
          borderRadius: BorderRadius.circular(HEShape.rXl),
          border: Border.all(color: HETheme.arenaRim),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 28,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ExpandHandle(
              expanded: _expanded,
              onTap: () => setState(() => _expanded = !_expanded),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.title != null) ...[
                        Text(
                          widget.title!.toUpperCase(),
                          style: HETheme.mono(
                            size: 10,
                            weight: FontWeight.w700,
                            color: HETheme.pfLavenderText,
                          ).copyWith(letterSpacing: 1.2),
                        ),
                        const SizedBox(height: 8),
                      ],
                      widget.child,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The expand/collapse control. Deliberately a real tappable target with a
/// semantic label rather than a bare drag gesture: a raw drag handle isn't
/// operable by keyboard or screen reader on its own, and "accessible
/// expand/collapse control" was an explicit requirement — the visual handle
/// bar IS the button, not decoration next to one, so there's exactly one
/// unambiguous target rather than a separate icon a screen-reader user has
/// to discover.
class _ExpandHandle extends StatelessWidget {
  const _ExpandHandle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: expanded
          ? 'Collapse this panel'
          : 'Expand this panel for more room',
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        child: ConstrainedBox(
          // 44x44 minimum touch target — the visible handle bar is much
          // shorter, but the tappable area around it clears the minimum.
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: HETheme.pfSecondaryViolet,
                    borderRadius: BorderRadius.circular(HEShape.rPill),
                  ),
                ),
                const SizedBox(height: 2),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_up_rounded,
                  size: 16,
                  color: HETheme.pfTextMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
