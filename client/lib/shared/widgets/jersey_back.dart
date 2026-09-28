import 'package:flutter/material.dart';

/// Deterministic club kit-color pairs, keyed by club name, used whenever a
/// club has no admin-set primaryColor/secondaryColor — every club still
/// renders a distinct, stable jersey without requiring color data entry for
/// all ~500 clubs up front.
const List<(Color, Color)> _kitFallbackPalette = [
  (Color(0xFF1A2E6B), Color(0xFFFFFFFF)), // navy / white
  (Color(0xFFC8102E), Color(0xFFFFFFFF)), // red / white
  (Color(0xFF00843D), Color(0xFFFFFFFF)), // green / white
  (Color(0xFF241773), Color(0xFFFDB927)), // purple / gold
  (Color(0xFF1C2C5B), Color(0xFFC4141C)), // navy / red
  (Color(0xFF15181C), Color(0xFFFFFFFF)), // near-black / white
  (Color(0xFF6CABDD), Color(0xFF1C2C5B)), // sky / navy
  (Color(0xFFDA020E), Color(0xFFFBE122)), // red / yellow
  (Color(0xFF132257), Color(0xFFC8102E)), // navy / red
  (Color(0xFFEF0107), Color(0xFF023474)), // red / navy
  (Color(0xFF6C1D45), Color(0xFF1BB1E7)), // claret / sky
  (Color(0xFFFDB913), Color(0xFF00529F)), // gold / blue
];

int _hash(String s) {
  var hash = 0;
  for (final code in s.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return hash;
}

(Color, Color) _kitFallback(String clubName) {
  if (clubName.isEmpty) return _kitFallbackPalette[0];
  return _kitFallbackPalette[_hash(clubName) % _kitFallbackPalette.length];
}

Color? _parseHex(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  final cleaned = hex.replaceFirst('#', '');
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return null;
  return Color(0xFF000000 | value);
}

/// Kit patterns. Every real club plays in one of these — an admin can pick
/// one explicitly per club (see AdminClub.kitPattern); a club left unset gets
/// one assigned deterministically by name instead, weighted toward [solid]
/// (~60%, both the most common real-world kit and the most legible behind a
/// printed number), so every club still looks distinct out of the box.
enum KitPattern {
  solid('Solid'),

  /// Solid base with a subtle self-coloured wave texture — the dominant look
  /// of modern manufactured kits (e.g. Everton's home shirt).
  tonal('Tonal'),
  stripes('Stripes'),
  pinstripes('Pinstripe'),
  hoops('Hoops'),
  halves('Halves'),
  quarters('Quarters'),
  sash('Sash'),
  centerBand('Center'),
  chestBand('Chest'),
  checkered('Checks'),
  sleeves('Sleeves'),
  gradient('Gradient');

  const KitPattern(this.label);
  final String label;
}

/// Weighted so an un-configured squad still looks like real football: mostly
/// solid/tonal (what most clubs actually wear), with stripes and hoops next
/// and the rarer designs showing up occasionally.
KitPattern _patternFor(String club) {
  if (club.isEmpty) return KitPattern.solid;
  switch (_hash(club) % 20) {
    case 9:
    case 10:
    case 11:
      return KitPattern.tonal;
    case 12:
    case 13:
    case 14:
      return KitPattern.stripes;
    case 15:
    case 16:
      return KitPattern.hoops;
    case 17:
      return KitPattern.sleeves;
    case 18:
      return KitPattern.pinstripes;
    case 19:
      return KitPattern.halves;
    default:
      return KitPattern.solid;
  }
}

/// Parses an admin-set pattern name (stored as the enum's `.name`, e.g.
/// "stripes") back into a [KitPattern]; unrecognized or missing → null, so
/// the caller falls back to the deterministic per-club pattern.
KitPattern? kitPatternFromName(String? name) {
  if (name == null) return null;
  for (final p in KitPattern.values) {
    if (p.name == name) return p;
  }
  return null;
}

/// Stable 1-99 shirt number derived from the player's card id — the game has
/// no real squad-number data, so this is a generated (not authoritative)
/// number, deterministic per player so it never changes between renders.
int squadNumberFor(String seed) {
  if (seed.isEmpty) return 1;
  return (_hash(seed) % 99) + 1;
}

/// How the shirt is sized into the space it's given.
enum JerseyFit {
  /// Whole shirt visible, letterboxed. For the details-modal hero, where
  /// there's room for the full garment.
  contain,

  /// Shirt fills the width and is cropped top/bottom as needed, keeping the
  /// number centred in what remains. For card image zones and pitch tiles,
  /// which are much wider than they are tall — `contain` there leaves the
  /// shirt marooned in the middle with dead space either side.
  cover,
}

/// Replaces player photos across the app: a generated jersey-back graphic in
/// the player's club colors, with their name and shirt number — entirely
/// rendered, no third-party photography involved, so there's no licensing
/// question for any player regardless of whether a legal photo exists.
class JerseyBack extends StatelessWidget {
  const JerseyBack({
    super.key,
    required this.playerName,
    required this.club,
    this.primaryColorHex,
    this.secondaryColorHex,
    this.tertiaryColorHex,
    this.numberSeed,
    this.kitNumber,
    this.kitPattern,
    this.fit = JerseyFit.cover,
  });

  final JerseyFit fit;

  final String playerName;
  final String club;
  final String? primaryColorHex;
  final String? secondaryColorHex;

  /// Collar and cuff trim. Falls back to the secondary when unset, which is
  /// what every kit did before this existed — so leaving it blank keeps a
  /// club looking exactly as it did.
  final String? tertiaryColorHex;

  /// Admin-set kit pattern — wins over the deterministic per-club one when
  /// present.
  final KitPattern? kitPattern;

  /// Seed for the generated squad number — defaults to [playerName] when
  /// omitted. Pass the card id where available for stability across name
  /// collisions. Ignored when [kitNumber] is set.
  final String? numberSeed;

  /// Admin-set shirt number — wins over the generated one when present.
  final int? kitNumber;

  /// Surname only, the way it actually appears on a shirt back ("MAC ALLISTER",
  /// not "A. MAC ALLISTER"). Handles the pool's "A. Surname" convention plus
  /// multi-word surnames and mononyms.
  String get _shirtName {
    final trimmed = playerName.trim();
    if (trimmed.isEmpty) return '';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.toUpperCase();
    // Drop leading initials ("A.", "J-M.") — whatever remains is the surname.
    final surname = parts.where((p) => !p.endsWith('.')).toList();
    return (surname.isEmpty ? parts.last : surname.join(' ')).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = _kitFallback(club);
    final primary = _parseHex(primaryColorHex) ?? fallback.$1;
    final secondary = _parseHex(secondaryColorHex) ?? fallback.$2;
    final tertiary = _parseHex(tertiaryColorHex) ?? secondary;
    final number = kitNumber ?? squadNumberFor(numberSeed ?? playerName);
    final pattern = kitPattern ?? _patternFor(club);

    // Print color is chosen against the PRIMARY (the dominant fabric), with a
    // contrasting outline — exactly how real shirt numbers stay readable over
    // stripes and hoops rather than needing a solid backing panel.
    final onLight = primary.computeLuminance() > 0.45;
    final printFill = onLight
        ? const Color(0xFF12161C)
        : const Color(0xFFFCFDFF);
    final printOutline = onLight
        ? const Color(0xFFFCFDFF)
        : const Color(0xFF12161C);

    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth.isFinite ? box.maxWidth : 160.0;
        final h = box.maxHeight.isFinite ? box.maxHeight : 160.0;

        // Fixed aspect so the shirt never stretches — the space it's given is
        // a different shape on a draft card, a pitch tile and the modal hero.
        const aspect = 1.06; // width / height
        double jw, jh, top;
        if (fit == JerseyFit.cover) {
          jw = w * 0.90;
          jh = jw / aspect;
          // Anchored just below the top rather than centred on the number:
          // that keeps the collar, shoulders and sleeves — the part that
          // actually reads as "football shirt" — and lets the hem run off
          // under the info strip, the way a card crops a player at the waist.
          // Centring instead showed only a mid-torso band with a number on it.
          top = jh > h ? -jh * 0.03 : (h - jh) / 2;
        } else {
          if (w / h > aspect) {
            jh = h * 0.94;
            jw = jh * aspect;
          } else {
            jw = w * 0.96;
            jh = jw / aspect;
          }
          top = (h - jh) / 2;
        }
        final rect = Rect.fromLTWH((w - jw) / 2, top, jw, jh);

        // The shirt name is only ever shown where the whole garment is on
        // display and there's real room for it — on a card or a pitch tile it
        // would collide with the rating/position badges, and the card already
        // prints the player's name in its info strip right below.
        final showName = h >= 150 && jh >= 120 && _shirtName.isNotEmpty;
        final numberSize = jh * (showName ? 0.30 : 0.34);
        final nameSize = (jh * 0.082).clamp(7.0, 15.0);

        // Clip so a `cover` shirt crops at this widget's bounds instead of
        // painting out over whatever sits below it (the card's info strip).
        return ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _JerseyPainter(
                    primary: primary,
                    secondary: secondary,
                    tertiary: tertiary,
                    pattern: pattern,
                    rect: rect,
                  ),
                ),
              ),
              if (showName)
                Positioned(
                  left: rect.left + jw * 0.16,
                  right: w - rect.right + jw * 0.16,
                  top: rect.top + jh * 0.235,
                  child: _PrintedText(
                    text: _shirtName,
                    fontSize: nameSize,
                    weight: FontWeight.w800,
                    letterSpacing: nameSize * 0.10,
                    fill: printFill,
                    outline: printOutline,
                    strokeWidth: nameSize * 0.16,
                  ),
                ),
              Positioned(
                left: rect.left,
                right: w - rect.right,
                top: rect.top + jh * (showName ? 0.36 : 0.32),
                child: _PrintedText(
                  text: '$number',
                  fontSize: numberSize,
                  weight: FontWeight.w900,
                  letterSpacing: numberSize * -0.02,
                  fill: printFill,
                  outline: printOutline,
                  strokeWidth: numberSize * 0.085,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Shirt lettering: a filled glyph over a contrasting outline, the way real
/// printed names/numbers are done — keeps it legible over stripes and hoops.
class _PrintedText extends StatelessWidget {
  const _PrintedText({
    required this.text,
    required this.fontSize,
    required this.weight,
    required this.letterSpacing,
    required this.fill,
    required this.outline,
    required this.strokeWidth,
  });

  final String text;
  final double fontSize;
  final FontWeight weight;
  final double letterSpacing;
  final Color fill;
  final Color outline;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    TextStyle base(Paint? fg, Color? color) => TextStyle(
      fontSize: fontSize,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      height: 1.0,
      color: color,
      foreground: fg,
    );

    // scaleDown rather than ellipsis: a long surname gets set smaller, the way
    // a real shirt printer fits "TRENT-ALEXANDER" across the same back panel,
    // instead of being cut to "TRENT-ALEXA…".
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            text,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            style: base(
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = strokeWidth
                ..strokeJoin = StrokeJoin.round
                ..color = outline,
              null,
            ),
          ),
          Text(
            text,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            style: base(null, fill),
          ),
        ],
      ),
    );
  }
}

/// Draws a jersey-back silhouette — sloped shoulders, sleeves joined to the
/// body at a real armpit seam, a dipped crew neckline with a collar band, and
/// a soft top-light gradient for a little depth.
class _JerseyPainter extends CustomPainter {
  _JerseyPainter({
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.pattern,
    required this.rect,
  });

  final Color primary;
  final Color secondary;

  /// Collar and cuff trim — distinct from [secondary], which is the pattern
  /// colour, so a striped shirt can carry a third accent on its trim.
  final Color tertiary;
  final KitPattern pattern;
  final Rect rect;

  /// Outline of the whole shirt (body + both sleeves), in [rect]'s space.
  Path _shirtPath() {
    final l = rect.left, t = rect.top, w = rect.width, h = rect.height;
    double x(double f) => l + w * f;
    double y(double f) => t + h * f;

    return Path()
      // Neckline — starts at the left of the collar, dips down, rises right.
      ..moveTo(x(0.385), y(0.035))
      ..quadraticBezierTo(x(0.50), y(0.145), x(0.615), y(0.035))
      // Right shoulder, then out along the sleeve top.
      ..quadraticBezierTo(x(0.68), y(0.020), x(0.745), y(0.055))
      ..lineTo(x(0.975), y(0.215))
      // Cuff.
      ..lineTo(x(0.915), y(0.410))
      // Underarm seam back in to the armpit.
      ..lineTo(x(0.775), y(0.335))
      ..quadraticBezierTo(x(0.760), y(0.300), x(0.775), y(0.275))
      // Right body side down to the hem.
      ..lineTo(x(0.800), y(0.975))
      ..quadraticBezierTo(x(0.800), y(0.995), x(0.775), y(0.995))
      // Hem.
      ..lineTo(x(0.225), y(0.995))
      ..quadraticBezierTo(x(0.200), y(0.995), x(0.200), y(0.975))
      // Left body side back up to the armpit.
      ..lineTo(x(0.225), y(0.275))
      ..quadraticBezierTo(x(0.240), y(0.300), x(0.225), y(0.335))
      // Left underarm seam out to the cuff.
      ..lineTo(x(0.085), y(0.410))
      ..lineTo(x(0.025), y(0.215))
      // Sleeve top back in to the left shoulder.
      ..lineTo(x(0.255), y(0.055))
      ..quadraticBezierTo(x(0.320), y(0.020), x(0.385), y(0.035))
      ..close();
  }

  /// The two sleeve regions, matching the outline's sleeve geometry exactly —
  /// used for the contrasting-sleeve kit.
  (Path, Path) _sleevePaths() {
    final l = rect.left, t = rect.top, w = rect.width, h = rect.height;
    double x(double f) => l + w * f;
    double y(double f) => t + h * f;

    final right = Path()
      ..moveTo(x(0.775), y(0.048))
      ..lineTo(x(0.745), y(0.055))
      ..lineTo(x(0.975), y(0.215))
      ..lineTo(x(0.915), y(0.410))
      ..lineTo(x(0.775), y(0.335))
      ..close();
    final left = Path()
      ..moveTo(x(0.225), y(0.048))
      ..lineTo(x(0.255), y(0.055))
      ..lineTo(x(0.025), y(0.215))
      ..lineTo(x(0.085), y(0.410))
      ..lineTo(x(0.225), y(0.335))
      ..close();
    return (left, right);
  }

  /// Nudges a colour toward black or white, whichever it contrasts with —
  /// used for the tone-on-tone texture, which has to stay clearly the same
  /// colour as the shirt rather than reading as a second kit colour.
  Color _shade(Color c, double amount) {
    final target = c.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    return Color.lerp(c, target, amount)!;
  }

  void _paintPattern(Canvas canvas) {
    final l = rect.left, t = rect.top, w = rect.width, h = rect.height;
    final band = Paint()..color = secondary;

    switch (pattern) {
      case KitPattern.solid:
        break;

      case KitPattern.tonal:
        // Horizontal wave lines in a near-primary tone — the subtle woven
        // texture most modern kits use, readable without competing with the
        // printed number on top.
        final tone = Paint()
          ..color = _shade(primary, 0.12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = h * 0.020;
        final waveH = h / 16;
        final segW = w / 5;
        for (var i = 0; i < 18; i++) {
          final y0 = t + waveH * i;
          final path = Path()..moveTo(l, y0);
          for (var s = 0; s < 5; s++) {
            final cx = l + segW * s + segW / 2;
            final x2 = l + segW * (s + 1);
            path.quadraticBezierTo(
              cx,
              y0 + waveH * 0.55 * (s.isEven ? -1 : 1),
              x2,
              y0,
            );
          }
          canvas.drawPath(path, tone);
        }

      case KitPattern.stripes:
        // 4 secondary stripes over primary → reads as a 9-stripe kit.
        const count = 4;
        final stripeW = w / 9;
        for (var i = 0; i < count; i++) {
          final left = l + stripeW * (1 + i * 2);
          canvas.drawRect(Rect.fromLTWH(left, t, stripeW, h), band);
        }

      case KitPattern.pinstripes:
        final gap = w / 11;
        final pinW = w * 0.014;
        for (var i = 1; i < 11; i++) {
          canvas.drawRect(
            Rect.fromLTWH(l + gap * i - pinW / 2, t, pinW, h),
            band,
          );
        }

      case KitPattern.hoops:
        const count = 3;
        final hoopH = h / 7;
        for (var i = 0; i < count; i++) {
          final top = t + hoopH * (1.4 + i * 2);
          canvas.drawRect(Rect.fromLTWH(l, top, w, hoopH), band);
        }

      case KitPattern.halves:
        canvas.drawRect(Rect.fromLTWH(l + w / 2, t, w / 2, h), band);

      case KitPattern.quarters:
        canvas.drawRect(Rect.fromLTWH(l + w / 2, t, w / 2, h / 2), band);
        canvas.drawRect(Rect.fromLTWH(l, t + h / 2, w / 2, h / 2), band);

      case KitPattern.sash:
        // Shoulder-to-opposite-hip band (River Plate / Peru / Rapid Vienna).
        canvas.drawPath(
          Path()
            ..moveTo(l, t + h * 0.10)
            ..lineTo(l + w, t + h * 0.62)
            ..lineTo(l + w, t + h * 0.88)
            ..lineTo(l, t + h * 0.36)
            ..close(),
          band,
        );

      case KitPattern.centerBand:
        // Wide vertical band down the middle (Ajax).
        canvas.drawRect(Rect.fromLTWH(l + w * 0.37, t, w * 0.26, h), band);

      case KitPattern.chestBand:
        // Sits above the number so it bands the chest rather than cutting
        // straight through the print.
        canvas.drawRect(Rect.fromLTWH(l, t + h * 0.20, w, h * 0.14), band);

      case KitPattern.checkered:
        // Croatia-style checkerboard.
        const cols = 5, rows = 7;
        final cw = w / cols, ch = h / rows;
        for (var r = 0; r < rows; r++) {
          for (var c = 0; c < cols; c++) {
            if ((r + c).isOdd) {
              canvas.drawRect(
                Rect.fromLTWH(l + cw * c, t + ch * r, cw, ch),
                band,
              );
            }
          }
        }

      case KitPattern.sleeves:
        final (left, right) = _sleevePaths();
        canvas.drawPath(left, band);
        canvas.drawPath(right, band);

      case KitPattern.gradient:
        // Primary held through the top third so the shirt still reads as its
        // own colour, fading into the secondary toward the hem.
        canvas.drawRect(
          rect,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [primary, secondary],
              stops: const [0.35, 1.0],
            ).createShader(rect),
        );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final shirt = _shirtPath();
    final l = rect.left, t = rect.top, w = rect.width, h = rect.height;
    double x(double f) => l + w * f;
    double y(double f) => t + h * f;

    // Soft contact shadow so the shirt lifts off the card background. Offset
    // further than it is blurred, and clipped to below the shoulder line, so
    // a light kit doesn't get a dark halo ringing its top edge.
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(rect.left - w, y(0.10), rect.right + w, rect.bottom + h),
    );
    canvas.drawPath(
      shirt.shift(Offset(0, h * 0.020)),
      Paint()
        ..color = const Color(0x3D000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.016),
    );
    canvas.restore();

    canvas.save();
    canvas.clipPath(shirt);

    // Base fabric + kit pattern.
    canvas.drawRect(rect, Paint()..color = primary);
    _paintPattern(canvas);

    // Top-light: a gentle lift at the shoulders fading to a slight shade at
    // the hem. Kept low-alpha so it reads as fabric, not as a gloss effect.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0x1FFFFFFF),
            Color(0x00FFFFFF),
            Color(0x1A000000),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(rect),
    );

    // Sleeve seams — a hairline of shade where each sleeve meets the body,
    // which is what actually makes the sleeves read as attached.
    final seam = Paint()
      ..color = const Color(0x22000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.008;
    canvas.drawLine(
      Offset(x(0.775), y(0.055)),
      Offset(x(0.775), y(0.335)),
      seam,
    );
    canvas.drawLine(
      Offset(x(0.225), y(0.055)),
      Offset(x(0.225), y(0.335)),
      seam,
    );

    // Collar band and cuffs are stroked ALONG the shirt's own edges, so half
    // of each stroke would fall outside the silhouette — drawn inside the
    // clip they read as bands sewn onto the shirt rather than as a blob
    // stuck to the outside of it (very visible on a black-on-white kit).
    canvas.drawPath(
      Path()
        ..moveTo(x(0.385), y(0.035))
        ..quadraticBezierTo(x(0.50), y(0.145), x(0.615), y(0.035)),
      Paint()
        ..color = tertiary
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.044
        ..strokeCap = StrokeCap.round,
    );

    final cuff = Paint()
      ..color = tertiary
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.046
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(
      Offset(x(0.975), y(0.215)),
      Offset(x(0.915), y(0.410)),
      cuff,
    );
    canvas.drawLine(
      Offset(x(0.025), y(0.215)),
      Offset(x(0.085), y(0.410)),
      cuff,
    );

    canvas.restore();

    // Crisp edge so the silhouette stays defined against a dark card.
    canvas.drawPath(
      shirt,
      Paint()
        ..color = const Color(0x33000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.006,
    );
  }

  @override
  bool shouldRepaint(covariant _JerseyPainter old) =>
      old.primary != primary ||
      old.secondary != secondary ||
      old.tertiary != tertiary ||
      old.pattern != pattern ||
      old.rect != rect;
}
