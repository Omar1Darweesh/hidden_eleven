import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';

/// A wider sibling of [ResponsiveLayout], opt-in and used only by the four
/// "First Touch Experience" screens (Home, Host Room, Join Room, Lobby).
///
/// [ResponsiveLayout] centers wide viewports into a fixed 480px column —
/// correct for other, unaudited screens this batch doesn't touch, but it
/// means a 1920px desktop and a 768px tablet render identically (just with
/// more dead space) for these four. This widget stays single-column always
/// — it is not a multi-column dashboard layout, just a wider column that
/// grows in two steps at the existing `HETheme` breakpoints, preserving a
/// fast, linear top-to-bottom reading order at every size.
class FirstTouchLayout extends StatelessWidget {
  const FirstTouchLayout({
    super.key,
    required this.child,
    this.horizontalPadding = 24.0,
    this.verticalPadding = 0.0,
  });

  final Widget child;
  final double horizontalPadding;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // Mobile used to cap at `double.infinity` ("no extra cap needed, the
    // Scaffold already bounds it"). That's true for a normal ancestor, but
    // Home wraps this in a `FittedBox`, which deliberately hands its child
    // UNBOUNDED width so it can measure natural size before scaling down.
    // With no real cap, that infinity reaches descendants like `Row(children:
    // [Expanded(...)])` in `_HowItWorks`, and `Expanded` cannot flex against
    // an infinite width — it threw "BoxConstraints forces an infinite width"
    // and blanked the whole screen on narrow viewports. Capping at the real
    // screen width fixes both ancestors: it's a no-op under a bounded
    // Scaffold and a genuine bound under FittedBox.
    final maxWidth = switch (width) {
      < HETheme.breakpointMobile => width,
      < HETheme.breakpointTablet => 560.0,
      _ => 680.0,
    };
    final isNarrow = width < HETheme.breakpointMobile;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isNarrow ? horizontalPadding : 0,
            vertical: verticalPadding,
          ),
          child: child,
        ),
      ),
    );
  }
}
