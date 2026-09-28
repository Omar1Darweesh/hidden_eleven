import 'dart:async';
import 'package:flutter/material.dart';

class CountdownTimerWidget extends StatefulWidget {
  final int? deadlineEpochMs;
  final String label;

  const CountdownTimerWidget({
    super.key,
    required this.deadlineEpochMs,
    required this.label,
  });

  @override
  State<CountdownTimerWidget> createState() => _CountdownTimerWidgetState();
}

class _CountdownTimerWidgetState extends State<CountdownTimerWidget> {
  Timer? _timer;
  int _secondsRemaining = 0;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemaining();
    });
  }

  void _updateRemaining() {
    if (widget.deadlineEpochMs == null) {
      if (mounted) setState(() => _secondsRemaining = 0);
      return;
    }
    final remaining =
        ((widget.deadlineEpochMs! - DateTime.now().millisecondsSinceEpoch) /
                1000)
            .ceil();
    final clamped = remaining < 0 ? 0 : remaining;
    if (mounted) setState(() => _secondsRemaining = clamped);
    if (clamped <= 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void didUpdateWidget(CountdownTimerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deadlineEpochMs != widget.deadlineEpochMs) {
      _timer?.cancel();
      _updateRemaining();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        _updateRemaining();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.deadlineEpochMs == null || _secondsRemaining <= 0) {
      return const SizedBox.shrink();
    }
    return Text(
      '${widget.label} ${_secondsRemaining}s',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: _secondsRemaining <= 10 ? Colors.red : Colors.white70,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
