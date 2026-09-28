import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hidden_eleven/app/he_theme.dart';

const _kDefaultItemExtent = 52.0;

const _kFallbackClubs = [
  'Arsenal',
  'Chelsea',
  'Liverpool FC',
  'Manchester City',
  'Real Madrid',
  'FC Barcelona',
  'Bayern Munich',
  'Paris Saint-Germain',
  'Juventus',
  'AC Milan',
  'Atlético Madrid',
  'Borussia Dortmund',
  'Inter Milan',
  'Tottenham Hotspur',
  'Manchester United',
  'Napoli',
  'Porto',
  'Benfica',
  'Sevilla',
  'Ajax',
];

/// Slot-machine-style club reveal that already knows the result before it
/// starts. Pass [resultClub] (from the server) so the animation always
/// decelerates and lands on exactly the right club — no mid-animation snap.
///
/// Deliberately a flat, `Timer`-driven text cycle (mirrors
/// `FormationRevealOverlay` in game_screen.dart) rather than a
/// `ListWheelScrollView`. A `ListWheelScrollView` was used here previously;
/// it renders every frame through a genuine 3D cylindrical-projection
/// `Matrix4` transform (`RenderListWheelViewport` — `perspective` is
/// asserted to always be `> 0`, so this 3D transform can't be dialed down to
/// a flat 2D one by tuning parameters, it's inherent to the widget). This
/// app previously "fixed" a reproducible native tombstone (SIGQUIT) on this
/// exact widget by forcing the Skia renderer via AndroidManifest's
/// `EnableImpeller=false` — but the currently pinned Flutter/engine build
/// compiles Android's Skia GL surface path out entirely behind a
/// `SLIMPELLER` flag (confirmed in the engine's
/// platform_view_android.cc — the `kSkiaOpenGLES` case is wrapped in
/// `#if !SLIMPELLER`), so that manifest flag is now silently inert and
/// Impeller/OpenGLES is unconditionally active again. Since the 3D-transform
/// codepath can't be avoided while using `ListWheelScrollView` and Impeller
/// can no longer be disabled, the fix is to stop using a 3D-transform widget
/// here at all, not to keep tuning the workaround that no longer works.
class ClubRouletteDrum extends StatefulWidget {
  const ClubRouletteDrum({
    super.key,
    required this.clubPool,
    required this.resultClub,
    required this.onComplete,
    this.itemExtent = _kDefaultItemExtent,
  });

  final List<String> clubPool;
  final String resultClub;
  final VoidCallback onComplete;

  /// Height of the drum's display row, in logical pixels. Defaults to 52.
  final double itemExtent;

  @override
  State<ClubRouletteDrum> createState() => _ClubRouletteDrumState();
}

class _ClubRouletteDrumState extends State<ClubRouletteDrum> {
  late final List<String> _pool;
  final _rng = Random();
  Timer? _cycleTimer;
  String _display = '';
  bool _landed = false;

  @override
  void initState() {
    super.initState();
    final source = widget.clubPool.isNotEmpty
        ? widget.clubPool
        : _kFallbackClubs;
    _pool = List<String>.of(source);
    _display = _pool[_rng.nextInt(_pool.length)];
    _scheduleCycle(70, 0);
  }

  @override
  void dispose() {
    _cycleTimer?.cancel();
    super.dispose();
  }

  // Slot-machine cycling that decelerates, then lands on the real result —
  // same deceleration shape as game_screen.dart's FormationRevealOverlay,
  // deliberately reused rather than reinvented.
  void _scheduleCycle(int interval, int elapsed) {
    _cycleTimer = Timer(Duration(milliseconds: interval), () {
      if (!mounted) return;
      setState(() => _display = _pool[_rng.nextInt(_pool.length)]);
      HapticFeedback.selectionClick();
      final nextInterval = (interval * 1.16).round();
      final nextElapsed = elapsed + interval;
      if (nextElapsed < 1500 && nextInterval < 250) {
        _scheduleCycle(nextInterval, nextElapsed);
      } else {
        _land();
      }
    });
  }

  void _land() {
    setState(() {
      _display = widget.resultClub;
      _landed = true;
    });
    HapticFeedback.mediumImpact();
    _cycleTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) widget.onComplete();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: widget.itemExtent,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _landed
                ? HETheme.pfAccentViolet.withValues(alpha: 0.12)
                : HETheme.pfAccentViolet.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _landed
                  ? HETheme.pfAccentViolet.withValues(alpha: 0.80)
                  : HETheme.pfAccentViolet.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
          // Fade+scale, not a 3D flip — see class doc comment for why.
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 120),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(
                scale: Tween(begin: 0.85, end: 1.0).animate(anim),
                child: child,
              ),
            ),
            child: Text(
              _display,
              key: ValueKey(_display),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _landed ? HETheme.pfAccentViolet : HETheme.pfTextPrimary,
                fontSize: (widget.itemExtent * 0.33).clamp(14.0, 26.0),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        if (_landed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.check_circle,
                  color: HETheme.pfAccentViolet,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    widget.resultClub,
                    style: const TextStyle(
                      color: HETheme.pfAccentViolet,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
