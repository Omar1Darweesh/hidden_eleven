import 'package:flutter/material.dart';

/// Settles [child] in with a gentle fade + rise on first build — the same
/// lightweight technique used on the home and result screens, factored out
/// so every entry/settings screen doesn't hand-roll its own
/// AnimationController for what is always the same effect.
///
/// Plays exactly once per mount: this widget owns the controller itself, so
/// wrapping a screen's whole body in it is enough — no external wiring.
class ScreenEntrance extends StatefulWidget {
  const ScreenEntrance({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 550),
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration duration;

  /// Optional hold before the entrance starts — lets a screen sequence
  /// itself after something else (e.g. a hero header) without a second
  /// controller.
  final Duration delay;

  @override
  State<ScreenEntrance> createState() => _ScreenEntranceState();
}

class _ScreenEntranceState extends State<ScreenEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(_fade);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion (OS-level `disableAnimations` OR the user's in-app
    // toggle — already combined into this one MediaQuery flag by app.dart)
    // jumps straight to the settled end state instead of animating in.
    // Checked here rather than initState: MediaQuery isn't available yet at
    // that point, and this only ever needs to run once per mount, which
    // didChangeDependencies already guarantees via _started.
    if (_started) return;
    _started = true;
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1.0;
      return;
    }
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  bool _started = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
