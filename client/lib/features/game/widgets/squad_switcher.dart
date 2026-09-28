import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_motion.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';

/// One squad in the switcher. Deliberately a flat view-model rather than a
/// `GamePlayer`, so this widget can be rendered in tests and previews without
/// constructing game state — and so it cannot accidentally reach for data it
/// has no business showing.
@immutable
class SquadTab {
  const SquadTab({
    required this.id,
    required this.label,
    required this.filledCount,
    this.isLocal = false,
    this.isCurrentTurn = false,
    this.isBot = false,
    this.isDisconnected = false,
    this.yellowPenalty = 0,
  });

  final String id;
  final String label;
  final int filledCount;
  final bool isLocal;
  final bool isCurrentTurn;
  final bool isBot;
  final bool isDisconnected;
  final int yellowPenalty;
}

/// Adapts [GameState] into the switcher's flat view-model.
///
/// Kept next to [SquadSwitcher] rather than inside `game_screen.dart` so the
/// mapping is testable on its own, and so the widget itself stays free of
/// game-state imports.
///
/// Note on AI players: `GamePlayer` carries no `isBot` flag — only the lobby's
/// `Player` model does — so [SquadTab.isBot] is left false here rather than
/// inferred. Adding the flag would mean changing a Riverpod state contract,
/// which this batch must not do. Connection status IS available and is wired.
List<SquadTab> buildSquadTabs(
  GameState game,
  List<String> orderedIds,
  String? localPlayerId,
) {
  final tabs = <SquadTab>[];
  for (final pid in orderedIds) {
    final player = game.players.where((p) => p.id == pid).firstOrNull;
    if (player == null) continue;
    tabs.add(
      SquadTab(
        id: pid,
        label: player.displayName,
        filledCount: game.pitches[pid]?.filledCount ?? 0,
        isLocal: pid == localPlayerId,
        isCurrentTurn: game.turn.activePlayerId == pid,
        isDisconnected: !player.isConnected,
        yellowPenalty: game.yellowPenalties[pid] ?? 0,
      ),
    );
  }
  return tabs;
}

/// The Squad Switcher — a segmented control seated on the arena frame's top
/// edge, replacing the row of free-floating chips.
///
/// ## Colour discipline
///
/// The active squad is **violet**, not emerald. Under Night Tactics emerald
/// means connected / ready / chemistry, so spending it on "which tab is
/// selected" made a status colour meaningless. Emerald survives here only as
/// the small live dot on whoever's turn it actually is — a real status.
/// Magenta appears only as a brief transition highlight on the moving
/// indicator, never as a permanent outline.
///
/// ## Status is never colour-only
///
/// Bot and disconnected states carry an icon and a semantics label, not just
/// a tint, so they survive colour-blindness and greyscale.
class SquadSwitcher extends StatelessWidget {
  const SquadSwitcher({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
    this.compact = false,
  });

  final List<SquadTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  /// Narrow layout: tighter padding, smaller type, count badge only.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (tabs.isEmpty) return const SizedBox.shrink();

    final height = compact ? 34.0 : 40.0;

    return SizedBox(
      height: height,
      child: DecoratedBox(
        // The track reads as part of the arena frame: same rim colour, same
        // plum, seated ON the frame edge rather than hovering above it.
        decoration: BoxDecoration(
          color: HETheme.pfSurfaceDeep.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(HEShape.rPill),
          border: Border.all(color: HETheme.arenaRim),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.38),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: LayoutBuilder(
            builder: (context, box) {
              final n = tabs.length;
              final segW = box.maxWidth / n;
              final safeIndex = selectedIndex.clamp(0, n - 1);

              return Stack(
                children: [
                  // The sliding indicator. One moving pill rather than each
                  // segment recolouring independently — that movement is what
                  // makes the control read as a single object.
                  AnimatedPositioned(
                    duration: HEMotion.select,
                    curve: HEMotion.easeOut,
                    left: segW * safeIndex,
                    top: 0,
                    bottom: 0,
                    width: segW,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            HETheme.pfAccentViolet.withValues(alpha: 0.30),
                            HETheme.pfSecondaryViolet.withValues(alpha: 0.22),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(HEShape.rPill),
                        border: Border.all(
                          color: HETheme.pfAccentViolet.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < n; i++)
                        SizedBox(
                          width: segW,
                          child: _Segment(
                            tab: tabs[i],
                            active: i == safeIndex,
                            compact: compact,
                            onTap: () => onChanged(i),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.tab,
    required this.active,
    required this.compact,
    required this.onTap,
  });

  final SquadTab tab;
  final bool active;
  final bool compact;
  final VoidCallback onTap;

  String get _statusWord {
    if (tab.isDisconnected) return 'disconnected';
    if (tab.isBot) return 'AI player';
    return 'connected';
  }

  @override
  Widget build(BuildContext context) {
    final label = tab.isLocal ? 'You' : tab.label;
    final fg = active ? HETheme.pfTextPrimary : HETheme.pfTextSecondary;

    return Semantics(
      button: true,
      selected: active,
      label:
          '$label, $_statusWord, ${tab.filledCount} picked'
          '${tab.isCurrentTurn ? ', their turn' : ''}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HEShape.rPill),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 11),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Live dot — the ONE emerald in this control, and it means a
                // real thing: it is this squad's turn right now.
                if (tab.isCurrentTurn) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: HETheme.pfSuccess,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: HETheme.pfSuccess.withValues(alpha: 0.6),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 5),
                ],
                // Status glyph — never colour alone.
                if (tab.isDisconnected)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.cloud_off_rounded,
                      size: compact ? 11 : 12,
                      color: HETheme.pfDanger,
                    ),
                  )
                else if (tab.isBot)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.smart_toy_outlined,
                      size: compact ? 11 : 12,
                      color: fg.withValues(alpha: 0.75),
                    ),
                  ),
                Flexible(
                  child: Text(
                    label,
                    style: HETheme.body(
                      size: compact ? 11.5 : 13,
                      weight: active ? FontWeight.w700 : FontWeight.w500,
                      color: fg,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (tab.yellowPenalty > 0) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.style_rounded,
                    size: compact ? 10 : 11,
                    color: HETheme.pfWarning,
                  ),
                ],
                SizedBox(width: compact ? 5 : 7),
                _CountBadge(
                  count: tab.filledCount,
                  active: active,
                  compact: compact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.count,
    required this.active,
    required this.compact,
  });

  final int count;
  final bool active;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: HEMotion.focus,
      padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: active
            ? HETheme.pfAccentViolet.withValues(alpha: 0.28)
            : HETheme.pfSurfaceRaised.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(HEShape.rPill),
      ),
      child: Text(
        '$count',
        style: HETheme.mono(
          size: compact ? 9.5 : 10.5,
          weight: FontWeight.w800,
          color: active ? HETheme.pfLavenderText : HETheme.pfTextMuted,
        ),
      ),
    );
  }
}
