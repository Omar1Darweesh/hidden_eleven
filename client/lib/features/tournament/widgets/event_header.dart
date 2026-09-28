import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';

/// The broadcast-style event header for Tournament Night.
///
/// Replaces the stock `AppBar` treatment with a compact lower-third: an event
/// eyebrow, the round as the headline, a status line, and the round pips —
/// one clear reading order of *event → round → status*, rather than four
/// items of equal weight.
///
/// Presentation only: every value is passed in by the caller from the
/// tournament state it already had.
class EventHeader extends StatelessWidget {
  const EventHeader({
    super.key,
    required this.roundLabel,
    this.eventLabel = 'TOURNAMENT NIGHT',
    this.status,
    this.statusColor,
    this.statusIcon,
    this.pips,
    this.leading,
    this.trailing,
    this.compact = false,
  });

  /// The headline — e.g. "Semi-finals".
  final String roundLabel;

  /// Small eyebrow above the headline.
  final String eventLabel;

  /// Optional short status line, e.g. "Ready check" or "Round live".
  final String? status;
  final Color? statusColor;
  final IconData? statusIcon;

  /// Round progress indicator supplied by the caller (the existing pips).
  final Widget? pips;

  final Widget? leading;
  final Widget? trailing;

  /// Narrow-width treatment: tighter spacing and a smaller headline.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accent = statusColor ?? HETheme.pfAccentViolet;

    return Semantics(
      header: true,
      label: [
        eventLabel,
        roundLabel,
        if (status != null) status,
      ].join(', '),
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          compact ? 12 : 18,
          compact ? 10 : 14,
          compact ? 12 : 18,
          compact ? 10 : 14,
        ),
        decoration: BoxDecoration(
          // Opaque, not translucent. The old fill faded `pfSurfaceDeep` to
          // 55% alpha, which read fine against a near-black page but let the
          // now-genuinely-plum atmosphere show straight through — the header
          // dissolved into its own background and stopped registering as a
          // surface at all. A broadcast lower-third has to sit *on* the scene.
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color.lerp(HETheme.pfSurfaceRaised, accent, 0.14)!,
              HETheme.pfSurfaceDeep,
            ],
            stops: const [0.0, 0.78],
          ),
          borderRadius: HEShape.lg,
          border: Border.all(
            color: accent.withValues(alpha: 0.45),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: accent.withValues(alpha: 0.12),
              blurRadius: 26,
              spreadRadius: -8,
            ),
          ],
        ),
        child: Row(
          children: [
            // Accent rule — the lower-third's signature edge.
            Container(
              width: 4,
              height: compact ? 36 : 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [accent, accent.withValues(alpha: 0.15)],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    eventLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 8.5 : 9.5,
                      letterSpacing: 2.4,
                      height: 1.2,
                      color: HETheme.pfTextSecondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    roundLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      // The event's headline: it should out-weigh every
                      // section label on the page, not match them.
                      fontSize: compact ? 20 : 27,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                      color: HETheme.pfTextPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  if (status != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (statusIcon != null) ...[
                          Icon(statusIcon, size: 11, color: accent),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            status!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (pips != null) ...[const SizedBox(width: 10), pips!],
            if (trailing != null) ...[const SizedBox(width: 4), trailing!],
          ],
        ),
      ),
    );
  }
}
