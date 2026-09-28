import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hidden_eleven/features/game/widgets/timer_ring.dart';

// Shown to the active player (full size, colored countdown).
// Shown to observers in a muted, smaller variant.

class TurnTimerWidget extends StatefulWidget {
  const TurnTimerWidget({
    super.key,
    required this.startedAt,
    required this.durationSeconds,
    this.muted = false,
    this.onUrgent,
    this.roundProgress,
  });

  final DateTime startedAt;
  final int durationSeconds;

  /// Optional outer round-progress ring — forwarded to [TimerRing]. See its
  /// doc comment for why the two readouts merged into one dial.
  final double? roundProgress;

  /// True when this is not the local player's turn (observer view).
  final bool muted;

  /// Fired once per countdown, the moment it first crosses into the urgent
  /// (< 25% remaining) range — used to play the ticking sound. Never called
  /// for a [muted] (observer) timer: the countdown urgency belongs to
  /// whoever's turn it actually is.
  final VoidCallback? onUrgent;

  @override
  State<TurnTimerWidget> createState() => _TurnTimerWidgetState();
}

class _TurnTimerWidgetState extends State<TurnTimerWidget>
    with SingleTickerProviderStateMixin {
  late Timer _ticker;
  double _remaining = 1.0; // 0.0 → 1.0 fraction of time left
  bool _urgentFired = false;

  /// Null under reduced motion — the urgency pulse then expresses itself
  /// through the ring's colour change alone, which is the accessible
  /// equivalent and was already carrying most of the signal.
  ///
  /// Previously this controller was created in `initState` and started with
  /// `repeat(reverse: true)` unconditionally, so it ran (scheduling frames)
  /// for the entire turn even though its output is only ever read in the
  /// final 25%, and it ignored the reduced-motion setting entirely.
  AnimationController? _pulseController;
  Animation<double>? _pulseAnim;
  bool _checkedMotion = false;

  @override
  void initState() {
    super.initState();
    _tick();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checkedMotion) return;
    _checkedMotion = true;
    if (MediaQuery.of(context).disableAnimations) return;

    final c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseController = c;
    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.08,
    ).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut));
  }

  void _tick() {
    final elapsed = DateTime.now().difference(widget.startedAt).inMilliseconds;
    final total = widget.durationSeconds * 1000;
    final remaining = ((total - elapsed) / total).clamp(0.0, 1.0);
    if (!mounted) return;
    setState(() => _remaining = remaining);
    if (!widget.muted && !_urgentFired && remaining < 0.25) {
      _urgentFired = true;
      widget.onUrgent?.call();
    }
  }

  @override
  void didUpdateWidget(TurnTimerWidget old) {
    super.didUpdateWidget(old);
    // A new turn (different startedAt) is a fresh countdown — let it fire
    // again rather than staying silenced by the previous turn's trigger.
    if (old.startedAt != widget.startedAt) _urgentFired = false;
  }

  @override
  void dispose() {
    _ticker.cancel();
    _pulseController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secondsLeft = (_remaining * widget.durationSeconds).ceil();
    final isPulse = !widget.muted && _remaining < 0.25;

    // The pulse now runs only while it is actually urgent, and stops again
    // if a new turn resets the countdown.
    final pulse = _pulseController;
    if (pulse != null) {
      if (isPulse && !pulse.isAnimating) {
        pulse.repeat(reverse: true);
      } else if (!isPulse && pulse.isAnimating) {
        pulse.stop();
        pulse.value = 0;
      }
    }

    Widget timer = TimerRing(
      remaining: _remaining,
      secondsLeft: secondsLeft,
      muted: widget.muted,
      roundProgress: widget.roundProgress,
    );

    final anim = _pulseAnim;
    if (isPulse && anim != null) {
      timer = AnimatedBuilder(
        animation: anim,
        builder: (_, child) => Transform.scale(scale: anim.value, child: child),
        child: timer,
      );
    }

    return timer;
  }
}
