import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';

/// How prominent a capsule's frame is.
///
/// Deliberately not uniform: if every surface wore the strong frame, none of
/// them would read as important. [FixtureEmphasis.focus] is reserved for the
/// things that genuinely lead — the final, the champion, your own result, the
/// live fixture — while ordinary rows and supporting statistics stay quiet.
enum FixtureEmphasis {
  /// Supporting content: stats rows, secondary panels. Minimal frame.
  quiet,

  /// The default fixture surface.
  standard,

  /// Reserved. Layered depth, stronger border, angular accent.
  focus,
}

/// The visual state a fixture is in.
///
/// **Presentation only.** This mirrors state the tournament model already
/// determines; nothing here decides, infers or changes match state, and the
/// mapping from match status to [FixtureState] lives at the call site exactly
/// as it did before.
enum FixtureState {
  /// Participants known, not started. Calm violet informational treatment.
  scheduled,

  /// In progress. Danger/red treatment plus an explicit label.
  live,

  /// Won and advancing. Success/emerald plus a check cue.
  winner,

  /// Knocked out. Muted plus an explicit label — never dimming alone.
  out,

  /// Genuinely unknown participant. Neutral placeholder, never a false name.
  unknown,

  /// Both finalists known, final not yet under way. Warm gold focus.
  finalSet,

  /// The tournament is decided. Champion emphasis.
  complete;

  /// Accent colour. Always paired with [label] and [icon] — colour is never
  /// the only carrier of meaning.
  Color get color => switch (this) {
    FixtureState.scheduled => HETheme.pfAccentViolet,
    FixtureState.live => HETheme.pfDanger,
    FixtureState.winner => HETheme.pfSuccess,
    FixtureState.out => HETheme.pfTextMuted,
    FixtureState.unknown => HETheme.pfTextMuted,
    FixtureState.finalSet => HETheme.pfGold,
    FixtureState.complete => HETheme.pfGold,
  };

  String get label => switch (this) {
    FixtureState.scheduled => 'NEXT',
    FixtureState.live => 'LIVE',
    FixtureState.winner => 'THROUGH',
    FixtureState.out => 'OUT',
    FixtureState.unknown => 'TBD',
    FixtureState.finalSet => 'FINAL SET',
    FixtureState.complete => 'CHAMPION',
  };

  IconData get icon => switch (this) {
    FixtureState.scheduled => Icons.schedule_rounded,
    FixtureState.live => Icons.podcasts_rounded,
    FixtureState.winner => Icons.check_circle_rounded,
    FixtureState.out => Icons.close_rounded,
    FixtureState.unknown => Icons.help_outline_rounded,
    FixtureState.finalSet => Icons.emoji_events_rounded,
    FixtureState.complete => Icons.emoji_events_rounded,
  };

  /// Whether the content behind this state should read as retired.
  bool get isDimmed => this == FixtureState.out;
}

/// The premium surface shared by bracket slots, match cards and the trophy
/// centre, so a fixture looks like the same object everywhere it appears.
///
/// Layered rather than flat: a plum glass body, a soft inner highlight along
/// the top edge, and — at [FixtureEmphasis.focus] — an angular accent notch
/// echoing the app's hex motif. Purely a container: it renders [child] and
/// takes no view on what a fixture means.
class FixtureCapsule extends StatelessWidget {
  const FixtureCapsule({
    super.key,
    required this.child,
    this.state,
    this.emphasis = FixtureEmphasis.standard,
    this.padding = const EdgeInsets.all(12),
    this.onTap,
    this.semanticLabel,
    this.accent,
  });

  final Widget child;

  /// Drives the accent colour and, when [showStateTag] applies, the corner
  /// tag. Null renders a neutral surface with no state chrome.
  final FixtureState? state;

  final FixtureEmphasis emphasis;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// Overrides the accent [state] would otherwise supply.
  ///
  /// Exists for callers that already own an established status→colour mapping
  /// (the match card's ready/live/complete accents, for one) and want the
  /// capsule's depth without having their vocabulary re-coloured.
  final Color? accent;

  bool get _isFocus => emphasis == FixtureEmphasis.focus;

  Color get _accent => accent ?? state?.color ?? HETheme.pfBorder;

  @override
  Widget build(BuildContext context) {
    final dimmed = state?.isDimmed ?? false;

    Widget body = Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _isFocus
              ? [
                  HETheme.pfSurfaceRaised,
                  Color.lerp(
                    HETheme.pfSurfaceDeep,
                    _accent,
                    0.06,
                  )!,
                ]
              : [
                  HETheme.pfSurfaceRaised,
                  HETheme.pfSurfaceDeep,
                ],
        ),
        borderRadius: _isFocus ? HEShape.lg : HEShape.md,
        border: Border.all(
          color: _accent.withValues(
            alpha: switch (emphasis) {
              FixtureEmphasis.quiet => 0.16,
              FixtureEmphasis.standard => 0.32,
              FixtureEmphasis.focus => 0.55,
            },
          ),
          width: _isFocus ? 1.5 : 1.0,
        ),
        boxShadow: _isFocus
            ? [
                BoxShadow(
                  color: _accent.withValues(alpha: 0.16),
                  blurRadius: 22,
                  offset: const Offset(0, 6),
                ),
              ]
            : emphasis == FixtureEmphasis.standard
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: child,
    );

    if (_isFocus) {
      body = Stack(
        children: [
          body,
          // Angular hex-motif frame on all four corners, not just one.
          //
          // A single small notch wasn't enough to separate a focus surface
          // from every other rounded rectangle on the page — the Trophy
          // Centre ended up reading as the *quietest* element rather than the
          // one that leads. Bracketing all four corners gives the reserved
          // surfaces their own silhouette at a glance.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _FocusFramePainter(color: _accent),
              ),
            ),
          ),
        ],
      );
    }

    // Eliminated, not erased. 0.42 disappeared once the page gained a real
    // plum background — a knocked-out participant still has to be readable,
    // since the OUT label is half of how that state is communicated.
    if (dimmed) body = Opacity(opacity: 0.62, child: body);

    if (onTap != null) {
      body = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: _isFocus ? HEShape.lg : HEShape.md,
          // Keeps every interactive capsule at a comfortable target size.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: body,
          ),
        ),
      );
    }

    if (semanticLabel != null) {
      body = Semantics(label: semanticLabel, excludeSemantics: true, child: body);
    }

    return body;
  }
}

/// A small state tag — icon **and** text, so the state survives greyscale and
/// colour-blindness. Used by callers that want the tag rendered inline.
class FixtureStateTag extends StatelessWidget {
  const FixtureStateTag({super.key, required this.state, this.compact = false});

  final FixtureState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceDeep,
        borderRadius: HEShape.pill,
        border: Border.all(color: state.color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(state.icon, size: compact ? 9 : 11, color: state.color),
          SizedBox(width: compact ? 3 : 5),
          Text(
            state.label,
            style: TextStyle(
              color: state.color,
              fontSize: compact ? 8 : 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chamfered corner brackets on all four corners of a focus-level surface.
///
/// Gives the reserved surfaces (Trophy Centre, live fixture, champion, Your
/// Result) a silhouette of their own, so they read as a different *kind* of
/// object rather than a slightly brighter rounded rectangle.
class _FocusFramePainter extends CustomPainter {
  const _FocusFramePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 1.5;
    const chamfer = 11.0;
    // Arms scale with the surface, so a small capsule doesn't get a frame
    // that meets in the middle.
    final armX = (size.width * 0.18).clamp(10.0, 34.0);
    final armY = (size.height * 0.22).clamp(10.0, 34.0);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.8);

    final r = size.width - inset;
    final b = size.height - inset;

    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(inset, inset + armY)
        ..lineTo(inset, inset + chamfer)
        ..lineTo(inset + chamfer, inset)
        ..lineTo(inset + armX, inset),
      paint,
    );
    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(r - armX, inset)
        ..lineTo(r - chamfer, inset)
        ..lineTo(r, inset + chamfer)
        ..lineTo(r, inset + armY),
      paint,
    );
    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(r, b - armY)
        ..lineTo(r, b - chamfer)
        ..lineTo(r - chamfer, b)
        ..lineTo(r - armX, b),
      paint,
    );
    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(inset + armX, b)
        ..lineTo(inset + chamfer, b)
        ..lineTo(inset, b - chamfer)
        ..lineTo(inset, b - armY),
      paint,
    );
  }

  @override
  bool shouldRepaint(_FocusFramePainter old) => old.color != color;
}
