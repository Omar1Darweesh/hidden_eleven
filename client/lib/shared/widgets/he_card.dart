import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/app/theme.dart'
    show HESpacing, HERadius, HETextStyles, HEColors;

enum HECardVariant { base, elevated, accent, gold, error }

/// Reusable themed surface container — replaces the repetitive
/// Container(BoxDecoration(surfaceElevated, divider border)) pattern.
///
/// Use [variant] to select the visual treatment:
///   - [base]     — surfaceElevated + subtle divider border (default)
///   - [elevated] — surfaceHigh + stronger border for modals / dropdowns
///   - [accent]   — accent-tinted bg + accent border (active state)
///   - [gold]     — gold-tinted bg + gold border (winner / premium highlight)
///   - [error]    — error-tinted bg + error border
class HECard extends StatelessWidget {
  const HECard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(HESpacing.xl),
    this.variant = HECardVariant.base,
    this.radius = HERadius.lg,
    this.onTap,
    this.clipBehavior = Clip.none,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final HECardVariant variant;
  final double radius;
  final VoidCallback? onTap;
  final Clip clipBehavior;

  Color get _bg => switch (variant) {
    HECardVariant.base => HETheme.pfSurfaceRaised,
    HECardVariant.elevated => HETheme.pfSurfaceGlass,
    HECardVariant.accent => HETheme.pfAccentViolet.withValues(alpha: 0.08),
    HECardVariant.gold => HETheme.pfGold.withValues(alpha: 0.07),
    HECardVariant.error => HETheme.pfDanger.withValues(alpha: 0.07),
  };

  Color get _border => switch (variant) {
    HECardVariant.base => HETheme.pfBorder,
    HECardVariant.elevated => HETheme.arenaRim,
    HECardVariant.accent => HETheme.pfSecondaryViolet,
    HECardVariant.gold => HETheme.pfGold.withValues(alpha: 0.45),
    HECardVariant.error => HETheme.pfDanger.withValues(alpha: 0.50),
  };

  double get _borderWidth => switch (variant) {
    HECardVariant.accent || HECardVariant.gold || HECardVariant.error => 1.5,
    _ => 1.0,
  };

  // Token-sourced shadows built here rather than via the legacy
  // `HEShadows.accent()`/`.gold()` helpers (theme.dart), which are wired to
  // the deprecated `HEColors` palette — building the shadow inline from the
  // same `HETheme` token used for the border keeps this one call site fully
  // on the Night Tactics system without needing a second shadow helper.
  List<BoxShadow>? get _shadow => switch (variant) {
    HECardVariant.accent => [
      BoxShadow(
        color: HETheme.pfAccentViolet.withValues(alpha: 0.18),
        blurRadius: 20,
        offset: const Offset(0, 4),
      ),
    ],
    HECardVariant.gold => [
      BoxShadow(
        color: HETheme.pfGold.withValues(alpha: 0.22),
        blurRadius: 20,
        offset: const Offset(0, 4),
      ),
    ],
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    Widget card = Container(
      clipBehavior: clipBehavior,
      padding: padding,
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: _border, width: _borderWidth),
        boxShadow: _shadow,
      ),
      child: child,
    );
    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: card,
      );
    }
    return card;
  }
}

// ── Shared panel header used by candidate / hidden-pick panels ────────────────

/// Consistent panel header: icon + title + subtitle row.
class HEPanelHeader extends StatelessWidget {
  const HEPanelHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.accent = false,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final iconColor = accent ? HETheme.pfAccentViolet : HETheme.pfTextSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: HESpacing.xl,
        vertical: HESpacing.md + 2,
      ),
      decoration: BoxDecoration(
        color: accent
            ? HETheme.pfAccentViolet.withValues(alpha: 0.09)
            : HETheme.pfSurfaceRaised,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(HERadius.lg),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(HERadius.sm),
            ),
            child: Icon(icon, color: iconColor, size: 17),
          ),
          const SizedBox(width: HESpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: HETextStyles.label),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: accent
                        ? HETheme.pfAccentViolet
                        : HETheme.pfTextPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: HESpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class HESectionLabel extends StatelessWidget {
  const HESectionLabel(this.text, {super.key, this.accent = false});

  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: HETextStyles.label.copyWith(
        color: accent ? HETheme.pfAccentViolet : HETheme.pfTextSecondary,
      ),
    );
  }
}

// ── Avatar (player initials with consistent colour) ───────────────────────────

class HEAvatar extends StatelessWidget {
  const HEAvatar({super.key, required this.name, this.size = 40, this.radius});

  final String name;
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    // `avatarColor` is an 8-hue data-visualisation palette (distinguishing
    // players by name), not a brand/UI colour — intentionally left as-is,
    // out of scope for the Night Tactics migration.
    final color = HEColors.avatarColor(name);
    final r = radius ?? size * 0.28;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(r),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            color: color,
            fontSize: size * 0.40,
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

// ── Chip / badge ──────────────────────────────────────────────────────────────

class HEBadge extends StatelessWidget {
  const HEBadge(this.label, {super.key, this.color, this.icon});

  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = color ?? HETheme.pfAccentViolet;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: HESpacing.sm,
        vertical: HESpacing.xs - 1,
      ),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(HERadius.xs),
        border: Border.all(color: c.withValues(alpha: 0.38)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: c),
            const SizedBox(width: 4),
          ],
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: c,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
