import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/widgets/pitch_view.dart'
    show pitchSlotCenter;

/// Which shared attribute a chemistry group represents.
///
/// Ported unchanged from the removed `ChemistryLinkPainter` so the priority
/// order below keeps its original meaning.
enum ChemistryGroupType { club, nationality, league }

/// The colour and motif for each group type. Colour is never the only
/// signal — every use pairs it with a letter and a distinct edge pattern.
extension ChemistryGroupTypeX on ChemistryGroupType {
  /// Club keeps cyan. This is now cyan's ONLY role in the app: it carries a
  /// real tactical meaning rather than being a UI identity colour.
  Color get color => switch (this) {
    ChemistryGroupType.club => HETheme.chemClub,
    ChemistryGroupType.nationality => HETheme.chemNationality,
    ChemistryGroupType.league => HETheme.chemLeague,
  };

  /// Single-letter marker, so the distinction survives colour-blindness and
  /// greyscale.
  String get letter => switch (this) {
    ChemistryGroupType.club => 'C',
    ChemistryGroupType.nationality => 'N',
    ChemistryGroupType.league => 'L',
  };

  String get label => switch (this) {
    ChemistryGroupType.club => 'CLUB',
    ChemistryGroupType.nationality => 'NATION',
    ChemistryGroupType.league => 'LEAGUE',
  };

  /// Aura edge motif — solid / dashed / dotted, matching the old link
  /// patterns so returning players read the same vocabulary.
  List<double>? get dashPattern => switch (this) {
    ChemistryGroupType.club => null, // solid
    ChemistryGroupType.nationality => const [7, 5], // dashed
    ChemistryGroupType.league => const [2, 6], // dotted
  };
}

/// A set of pitch slots sharing one attribute.
///
/// **Presentation-only — never evaluates or influences chemistry scoring.**
/// This is a pure visual grouping over [PitchSlot.cardClub] /
/// [PitchSlot.cardNationality] / [PitchSlot.cardLeague] — the same three
/// fields the audited [ChemistryEvaluator] reads, but nothing here calls into
/// that evaluator and nothing here computes, caches or infers a score,
/// satisfied state, or reward value.
@immutable
class ChemistryGroup {
  const ChemistryGroup({
    required this.type,
    required this.value,
    required this.slots,
  });

  final ChemistryGroupType type;

  /// The shared attribute value (club name, nationality, league).
  final String value;

  final List<PitchSlot> slots;

  int get size => slots.length;
}

/// Minimum members before a group is worth drawing an aura for.
///
/// Two players sharing a league is an accident; three is a pattern. This
/// threshold is the whole reason constellations read as calm where the old
/// pairwise link web did not.
const int kMinConstellationSize = 3;

/// Computes the chemistry groups present in [slots].
///
/// Replaces the removed `computeChemistryLinks`, which returned *pairs*. The
/// eligibility rule and the priority order are ported verbatim:
///
///  * Only filled, non-red-carded slots count — an empty slot has no card,
///    and a red-carded card is chemistry-nullified, mirroring how
///    `_FilledCard` already excludes red-carded cards from the lineup it
///    hands to [ChemistryEvaluator].
///  * Priority is **club > nationality > league**, and a slot belongs to at
///    most ONE group: its highest-priority one. This is the group analogue of
///    the old "only the single highest-priority link per pair" rule, and it
///    is what stops a player appearing inside three overlapping auras.
///
/// Returns groups of at least [minSize] members, ordered by priority then by
/// descending size.
List<ChemistryGroup> computeChemistryGroups(
  List<PitchSlot> slots, {
  int minSize = kMinConstellationSize,
}) {
  final eligible = slots.where((s) => s.isFilled && !s.isRedCarded).toList();
  if (eligible.length < minSize) return const [];

  final groups = <ChemistryGroup>[];
  // Slots already claimed by a higher-priority group.
  final claimed = <int>{};

  // Ordered by priority — club first, so it claims its members before
  // nationality gets a chance, and so on.
  const order = [
    ChemistryGroupType.club,
    ChemistryGroupType.nationality,
    ChemistryGroupType.league,
  ];

  String? valueOf(PitchSlot s, ChemistryGroupType t) => switch (t) {
    ChemistryGroupType.club => s.cardClub,
    ChemistryGroupType.nationality => s.cardNationality,
    ChemistryGroupType.league => s.cardLeague,
  };

  for (final type in order) {
    final buckets = <String, List<PitchSlot>>{};
    for (final s in eligible) {
      if (claimed.contains(s.index)) continue;
      final v = valueOf(s, type);
      if (v == null || v.isEmpty) continue;
      buckets.putIfAbsent(v, () => []).add(s);
    }

    final found =
        buckets.entries
            .where((e) => e.value.length >= minSize)
            .map(
              (e) => ChemistryGroup(type: type, value: e.key, slots: e.value),
            )
            .toList()
          ..sort((a, b) => b.size.compareTo(a.size));

    for (final g in found) {
      groups.add(g);
      for (final s in g.slots) {
        claimed.add(s.index);
      }
    }
  }

  return groups;
}

/// The single group whose aura should be drawn in the normal live pitch view.
///
/// At most ONE aura shows at a time — the highest-priority, then largest.
/// Showing several at once reproduces exactly the visual conflict the
/// pairwise link web had.
ChemistryGroup? primaryConstellation(List<PitchSlot> slots) {
  final groups = computeChemistryGroups(slots);
  return groups.isEmpty ? null : groups.first;
}

/// Which group (if any) a given slot belongs to — drives the per-card marker.
///
/// Uses the full group list rather than just the primary, so a card can show
/// its marker even when its group isn't the one currently drawing an aura.
Map<int, ChemistryGroupType> constellationMarkers(List<PitchSlot> slots) {
  final markers = <int, ChemistryGroupType>{};
  for (final g in computeChemistryGroups(slots)) {
    for (final s in g.slots) {
      markers[s.index] = g.type;
    }
  }
  return markers;
}

/// Paints ONE soft group aura behind the cards.
///
/// Deliberately not a line, arrow, route or selection boundary: it is a
/// rounded, low-opacity region hugging the cluster, drawn beneath the cards
/// and never interactive. If the region would be too small or too elongated
/// to read as a cluster, it suppresses itself rather than forcing a shape —
/// see [_shouldDraw].
class ConstellationAuraPainter extends CustomPainter {
  const ConstellationAuraPainter({required this.group});

  final ChemistryGroup? group;

  @override
  void paint(Canvas canvas, Size size) {
    final g = group;
    if (g == null) return;

    final points = g.slots
        .map((s) => pitchSlotCenter(s, size.width, size.height))
        .toList();
    if (points.length < kMinConstellationSize) return;
    if (!_shouldDraw(points, size)) return;

    final path = _blobAround(points, size);
    final color = g.type.color;

    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.075));

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color.withValues(alpha: 0.32);

    final dash = g.type.dashPattern;
    if (dash == null) {
      canvas.drawPath(path, stroke);
    } else {
      _drawDashed(canvas, path, stroke, dash);
    }
  }

  /// Suppression rule: an aura that is extremely elongated reads as a line or
  /// a passing lane — exactly the thing constellations exist to replace — so
  /// we simply don't draw it. Better no aura than a misleading one.
  bool _shouldDraw(List<Offset> pts, Size size) {
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final p in pts) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    final w = maxX - minX;
    final h = maxY - minY;
    if (w <= 1 || h <= 1) return false;

    final aspect = math.max(w / h, h / w);
    // Beyond ~5:1 the hull is visually a stripe, not a cluster.
    return aspect <= 5.0;
  }

  /// A rounded convex hull around the cluster, inflated so it sits behind the
  /// cards rather than clipping them.
  Path _blobAround(List<Offset> pts, Size size) {
    final hull = _convexHull(pts);
    // Inflate from the centroid so the region comfortably contains the cards.
    final cx = hull.map((p) => p.dx).reduce((a, b) => a + b) / hull.length;
    final cy = hull.map((p) => p.dy).reduce((a, b) => a + b) / hull.length;
    final pad = size.width * 0.085;

    final expanded = hull.map((p) {
      final dx = p.dx - cx;
      final dy = p.dy - cy;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len == 0) return p;
      return Offset(p.dx + dx / len * pad, p.dy + dy / len * pad);
    }).toList();

    // Catmull-Rom-ish smoothing via quadratic midpoints — cheap, and gives
    // the soft organic edge a polygon can't.
    final path = Path();
    final n = expanded.length;
    if (n < 3) return path;

    Offset mid(Offset a, Offset b) =>
        Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);

    path.moveTo(
      mid(expanded[n - 1], expanded[0]).dx,
      mid(expanded[n - 1], expanded[0]).dy,
    );
    for (var i = 0; i < n; i++) {
      final cur = expanded[i];
      final next = expanded[(i + 1) % n];
      final m = mid(cur, next);
      path.quadraticBezierTo(cur.dx, cur.dy, m.dx, m.dy);
    }
    path.close();
    return path;
  }

  /// Andrew's monotone chain.
  List<Offset> _convexHull(List<Offset> input) {
    final pts = List<Offset>.from(input)
      ..sort(
        (a, b) => a.dx == b.dx ? a.dy.compareTo(b.dy) : a.dx.compareTo(b.dx),
      );
    if (pts.length <= 3) return pts;

    double cross(Offset o, Offset a, Offset b) =>
        (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);

    final lower = <Offset>[];
    for (final p in pts) {
      while (lower.length >= 2 &&
          cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }
    final upper = <Offset>[];
    for (final p in pts.reversed) {
      while (upper.length >= 2 &&
          cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }
    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  void _drawDashed(Canvas canvas, Path path, Paint paint, List<double> dash) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      var draw = true;
      var i = 0;
      while (distance < metric.length) {
        final len = dash[i % dash.length];
        if (draw) {
          canvas.drawPath(
            metric.extractPath(
              distance,
              math.min(distance + len, metric.length),
            ),
            paint,
          );
        }
        distance += len;
        draw = !draw;
        i++;
      }
    }
  }

  @override
  bool shouldRepaint(ConstellationAuraPainter old) =>
      old.group?.type != group?.type ||
      old.group?.value != group?.value ||
      old.group?.size != group?.size;
}

/// The small per-card chemistry marker.
///
/// Carries a letter as well as a colour, and is sized to sit in a card's
/// corner without covering rating, name, position, or the existing `+N`
/// chemistry reward badge.
class ConstellationMarker extends StatelessWidget {
  const ConstellationMarker({super.key, required this.type, this.size = 13});

  final ChemistryGroupType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${type.label.toLowerCase()} chemistry',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: type.color,
          shape: BoxShape.circle,
          border: Border.all(
            color: HETheme.pfBgVoid.withValues(alpha: 0.55),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: Text(
            type.letter,
            style: TextStyle(
              color: HETheme.pfBgVoid,
              fontSize: size * 0.62,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}

/// The labelled chip that names the aura's group, e.g. "CLUB ×3".
class ConstellationLabel extends StatelessWidget {
  const ConstellationLabel({super.key, required this.group});

  final ChemistryGroup group;

  @override
  Widget build(BuildContext context) {
    final c = group.type.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: HETheme.pfBgVoid.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Text(
        '${group.type.label} ×${group.size}',
        style: HETheme.mono(
          size: 9,
          weight: FontWeight.w800,
          color: c,
        ).copyWith(letterSpacing: 0.8),
      ),
    );
  }
}
