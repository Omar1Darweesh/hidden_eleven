import 'package:flutter/material.dart';

/// Cinematic entrance for a screen's one hero element (a logo, a branded
/// header panel) — fade + a single scale-in from 92% with a brief
/// `easeOutBack` overshoot settle, once. Self-contained (owns its own
/// `AnimationController`/ticker) so it drops onto any screen's hero without
/// that screen needing to become a `TickerProviderStateMixin` itself —
/// unlike `ScreenEntrance` (fade + slide only), this is reserved for the
/// one element per screen that deserves to feel like it "arrived."
///
/// Respects `MediaQuery.disableAnimations`: jumps straight to the settled
/// state instead of animating in.
class HeroEntrance extends StatefulWidget {
  const HeroEntrance({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 650),
  });

  final Widget child;
  final Duration duration;

  @override
  State<HeroEntrance> createState() => _HeroEntranceState();
}

class _HeroEntranceState extends State<HeroEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween(
      begin: 0.92,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1.0;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}
