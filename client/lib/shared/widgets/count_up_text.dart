import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_motion.dart';

/// Counts a number up to [value] once, then holds it.
///
/// Shared by the Your Result score and the Points Breakdown total so there is
/// exactly one reduced-motion-correct implementation of this rather than two.
///
/// Guarantees, all covered by tests:
///  * **Never delays data.** Under reduced motion the final number is the
///    first and only thing painted — there is no count and no controller.
///  * **Never blocks input.** This is a `Text`; it takes no gestures and
///    nothing waits on it. Controls beside it are live from frame one.
///  * **Never replays.** The count runs once for a given [value]. Rebuilds —
///    from a `game_state` broadcast, a provider update, a tab switch, an
///    orientation change — re-render at the settled number. Only a genuinely
///    different [value] starts a new count, which is a real data change
///    rather than a repaint.
class CountUpText extends StatefulWidget {
  const CountUpText({
    super.key,
    required this.value,
    required this.style,
    this.suffix = '',
    this.duration = HEMotion.entrance,
    this.textAlign,
  });

  /// The final number. Always what a reader ends up seeing.
  final int value;

  final TextStyle style;

  /// Rendered immediately after the number, e.g. " pts".
  final String suffix;

  /// Must be an `HEMotion` token.
  final Duration duration;

  final TextAlign? textAlign;

  @override
  State<CountUpText> createState() => _CountUpTextState();
}

// TickerProviderStateMixin, not the Single variant: when [value] genuinely
// changes, this disposes the old controller and builds a new one, and the
// single-ticker mixin asserts on a second ticker from the same State.
class _CountUpTextState extends State<CountUpText>
    with TickerProviderStateMixin {
  AnimationController? _controller;

  /// The value this widget has already counted to. Guards against re-running
  /// on any rebuild that isn't an actual change of number.
  int? _countedTo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeStart();
  }

  @override
  void didUpdateWidget(CountUpText old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _maybeStart();
  }

  void _maybeStart() {
    if (_countedTo == widget.value) return;
    _countedTo = widget.value;

    // Reduced motion: no controller is constructed at all — not one that is
    // built and left idle. A paused controller still schedules frames.
    if (HEMotion.reduced(context)) {
      _controller?.dispose();
      _controller = null;
      if (mounted) setState(() {});
      return;
    }

    _controller?.dispose();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
    setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    // No controller (reduced motion, or already settled) → the final number.
    if (controller == null) return _text(widget.value);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = HEMotion.easeOut.transform(controller.value);
        return _text((widget.value * t).round());
      },
    );
  }

  Widget _text(int shown) => Text(
    '$shown${widget.suffix}',
    textAlign: widget.textAlign,
    style: widget.style,
  );
}
