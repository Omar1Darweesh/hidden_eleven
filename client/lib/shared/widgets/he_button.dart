import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/shared/widgets/he_visual_style.dart';

enum HEButtonVariant { primary, secondary, ghost, danger }

class HEButton extends StatelessWidget {
  const HEButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = HEButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.small = false,
    this.color,
    this.style = HEVisualStyle.standard,
  });

  final String label;
  final VoidCallback? onPressed;
  final HEButtonVariant variant;
  final IconData? icon;
  final bool loading;

  /// When true, reduces height for tighter layouts (44 px instead of 52 px).
  final bool small;

  /// Optional background override for [HEButtonVariant.primary], for a
  /// state-specific semantic color (e.g. amber for "confirm a pending
  /// swap") that isn't the app's default accent green. Ignored while
  /// disabled — the standard muted disabled look always wins, so every
  /// button in the app still shares one disabled treatment.
  final Color? color;

  /// Migration bridge only — both values now render identically (Night
  /// Tactics violet). See [HEVisualStyle]'s doc comment; do not branch on
  /// this in new code.
  final HEVisualStyle style;

  Size get _minSize =>
      small ? const Size.fromHeight(44) : const Size.fromHeight(52);

  Widget _content(Color spinnerColor) {
    if (loading) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: spinnerColor),
      );
    }
    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      );
    }
    return Text(label);
  }

  Widget _child() {
    return switch (variant) {
      HEButtonVariant.primary => ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          minimumSize: _minSize,
          // Left null when enabled with no override — that defers entirely
          // to the app-wide ElevatedButtonTheme (theme.dart), which already
          // supplies the Night Tactics violet fill/disabled treatment
          // centrally. Only a caller-supplied [color] (a state-specific
          // semantic override, e.g. amber for "confirm a pending swap")
          // sets this explicitly.
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HETheme.radiusMd),
          ),
        ),
        child: _content(HETheme.pfTextPrimary),
      ),
      HEButtonVariant.secondary => OutlinedButton(
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: _minSize,
          foregroundColor: HETheme.pfTextPrimary,
          side: const BorderSide(color: HETheme.pfSecondaryViolet, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HETheme.radiusMd),
          ),
        ),
        child: _content(HETheme.pfTextPrimary),
      ),
      HEButtonVariant.ghost => TextButton(
        onPressed: loading ? null : onPressed,
        style: TextButton.styleFrom(
          foregroundColor: HETheme.pfTextSecondary,
          minimumSize: _minSize,
        ),
        child: _content(HETheme.pfTextSecondary),
      ),
      HEButtonVariant.danger => TextButton(
        onPressed: loading ? null : onPressed,
        style: TextButton.styleFrom(
          foregroundColor: HETheme.pfDanger,
          minimumSize: _minSize,
        ),
        child: _content(HETheme.pfDanger),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    // Every button in the app routes through here, so a single press-scale
    // here is the cheapest possible way to give the whole game a tactile
    // "physical" feel — previously every tap had only the default Material
    // ripple, with zero motion on the button itself.
    return _PressScale(enabled: onPressed != null && !loading, child: _child());
  }
}

/// Wraps [child] with a subtle press-down scale. Uses `Listener` rather than
/// a `GestureDetector`/`InkWell` of its own: `Listener` observes raw pointer
/// events without entering the gesture arena, so it can drive this animation
/// purely as an observer while the real button underneath keeps its own tap
/// handling, ripple, and hit-testing completely untouched.
class _PressScale extends StatefulWidget {
  const _PressScale({required this.child, required this.enabled});
  final Widget child;
  final bool enabled;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: widget.enabled ? (_) => _setPressed(true) : null,
      onPointerUp: widget.enabled ? (_) => _setPressed(false) : null,
      onPointerCancel: widget.enabled ? (_) => _setPressed(false) : null,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
