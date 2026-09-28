import 'package:flutter/material.dart';

const double kNarrowBreakpoint = 600.0;
const double kContentMaxWidth = 480.0;

/// Centers content with a max-width on wide screens (web/tablet).
/// On narrow screens it fills width with horizontal padding.
class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
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
    final isWide = width > kNarrowBreakpoint;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isWide ? kContentMaxWidth : double.infinity,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 0 : horizontalPadding,
            vertical: verticalPadding,
          ),
          child: child,
        ),
      ),
    );
  }
}
