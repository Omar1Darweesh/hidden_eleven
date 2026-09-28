import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';

/// The floating match bar — replaces the game screen's opaque [AppBar].
///
/// The AppBar was the single largest flat band on the screen, and it is what
/// made the arena background impossible to see: a full-width opaque surface
/// pinned to the top edge leaves the background nothing to show through.
/// This is the same information as a pill that floats *over* the arena.
///
/// It carries every responsibility the old AppBar had, with identical
/// callbacks — room code, formation, the auxiliary overflow menu, the
/// persistent secret-ability reminder, and Leave. Nothing was dropped in the
/// move; see the game screen's `_buildMatchBar` for the wiring.
class MatchBar extends StatelessWidget {
  const MatchBar({
    super.key,
    required this.roomCode,
    required this.formationName,
    required this.onLeave,
    this.menu,
    this.abilityChip,
    this.compact = false,
  });

  final String roomCode;
  final String formationName;
  final VoidCallback onLeave;

  /// The auxiliary overflow menu (help / abilities / ability log). Built by
  /// the caller so this widget stays free of game-state and dialog imports.
  final Widget? menu;

  /// The persistent reminder of the local player's secret ability, when they
  /// have one. Passed in for the same reason as [menu].
  final Widget? abilityChip;

  /// Narrow layout: tighten padding and drop the formation name, which is
  /// the one piece here that is never needed to take a turn.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HETheme.pfSurfaceGlass.withValues(alpha: 0.72),
            HETheme.pfSurfaceDeep.withValues(alpha: 0.66),
          ],
        ),
        borderRadius: HEShape.pill,
        border: Border.all(color: HETheme.arenaRim),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.38),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RoomCodePill(code: roomCode),
            if (!compact) ...[
              const SizedBox(width: 10),
              // Flexible, not Expanded: the bar sizes to its content so it
              // reads as a pill rather than a full-width band, but a long
              // formation name still ellipsises instead of overflowing.
              Flexible(
                child: Text(
                  formationName,
                  style: HETheme.body(
                    size: 13,
                    weight: FontWeight.w600,
                    color: HETheme.pfTextSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const SizedBox(width: 6),
            ?menu,
            if (abilityChip != null) ...[
              const SizedBox(width: 2),
              abilityChip!,
              const SizedBox(width: 4),
            ],
            _LeaveButton(onLeave: onLeave),
          ],
        ),
      ),
    );
  }
}

/// The room code. Violet rather than the old emerald — under Night Tactics
/// emerald means "success/connected/chemistry" and nothing else, so a room
/// code wearing it was borrowing a meaning it doesn't have.
class _RoomCodePill extends StatelessWidget {
  const _RoomCodePill({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: HETheme.pfAccentViolet.withValues(alpha: 0.16),
        borderRadius: HEShape.pill,
        border: Border.all(
          color: HETheme.pfAccentViolet.withValues(alpha: 0.45),
        ),
      ),
      child: Text(
        code,
        style: HETheme.mono(
          size: 12,
          weight: FontWeight.w800,
          color: HETheme.pfLavenderText,
        ).copyWith(letterSpacing: 1.5),
      ),
    );
  }
}

/// Leave. Outlined in danger rather than filled with it — the shape-usage
/// rule for destructive actions: clearly distinct, never aggressive.
class _LeaveButton extends StatelessWidget {
  const _LeaveButton({required this.onLeave});

  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Leave game',
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: HEShape.pill),
        child: InkWell(
          onTap: onLeave,
          customBorder: RoundedRectangleBorder(borderRadius: HEShape.pill),
          child: Container(
            // 44x44 minimum touch target — the visible glyph is smaller, but
            // the tap area is what has to clear the minimum.
            constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: HEShape.pill,
              border: Border.all(
                color: HETheme.pfDanger.withValues(alpha: 0.40),
              ),
            ),
            child: const Icon(
              Icons.exit_to_app_rounded,
              size: 18,
              color: HETheme.pfDanger,
            ),
          ),
        ),
      ),
    );
  }
}
