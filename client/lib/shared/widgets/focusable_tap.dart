import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hidden_eleven/app/he_theme.dart';

/// Wraps a bare `GestureDetector`-driven chip/selector in real keyboard
/// support: tab-focusable, Enter/Space activates it, and a visible focus
/// ring paints when focused — none of which a plain `GestureDetector` +
/// `AnimatedContainer` chip gets for free, unlike Material's built-in
/// button widgets. Used by the chip-style selectors on Host Room and Join
/// Room (turn timer, league, formation, bot count, code entry, etc.).
class FocusableTap extends StatefulWidget {
  const FocusableTap({
    super.key,
    required this.onTap,
    required this.child,
    this.borderRadius,
  });

  final VoidCallback onTap;
  final Widget child;
  final BorderRadius? borderRadius;

  @override
  State<FocusableTap> createState() => _FocusableTapState();
}

class _FocusableTapState extends State<FocusableTap> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onTap(),
        ),
      },
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          decoration: _focused
              ? BoxDecoration(
                  borderRadius: widget.borderRadius,
                  border: Border.all(color: HETheme.pfAccentViolet, width: 2),
                )
              : null,
          child: widget.child,
        ),
      ),
    );
  }
}
