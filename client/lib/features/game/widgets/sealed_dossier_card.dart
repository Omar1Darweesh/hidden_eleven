import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_motion.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';

/// The visual state of a face-down dossier.
///
/// Deliberately an explicit enum rather than a pile of booleans: it makes it
/// impossible to construct a contradictory combination (selected AND
/// unavailable), and it keeps the widget's inputs enumerable — which matters
/// for the leak-prevention contract below.
enum DossierState {
  /// Sealed, not this player's turn. Calm, low contrast.
  resting,

  /// This player's turn — tappable.
  available,

  /// Chosen but not yet confirmed. Lifted, gold rim.
  selected,

  /// Locked in by the local player. Seal closed.
  locked,

  /// Already taken by someone else, or otherwise not choosable this turn.
  unavailable,
}

/// The "sealed dossier" — a face-down hidden-pick slot.
///
/// Under Night Tactics this is a **file-folder silhouette** (a tab notch cut
/// into the top-left edge) rather than a plain rounded rectangle, layered
/// plum with a gold seal. Gold is the app's reserved hidden/classified/reveal
/// colour, so it stays.
///
/// ## Leak-prevention contract — do not weaken
///
/// Every dossier renders from nothing but [slotNumber], [state] and [onTap].
/// **No card identity, size, colour, shadow, pattern or timing may ever vary
/// by what is actually underneath a sealed slot.** Do not add a parameter
/// here that could vary by hidden content — if a caller wants to distinguish
/// dossiers visually, that is a bug, not a feature. `dossier_shuffle_test`
/// asserts two decks with different cards render identically.
class SealedDossierCard extends StatelessWidget {
  const SealedDossierCard({
    super.key,
    required this.slotNumber,
    required this.state,
    this.onTap,
  });

  final int slotNumber;
  final DossierState state;
  final VoidCallback? onTap;

  bool get _tappable => onTap != null && state != DossierState.unavailable;

  bool get _lit =>
      state == DossierState.available ||
      state == DossierState.selected ||
      state == DossierState.locked;

  Color get _accent => switch (state) {
    DossierState.available ||
    DossierState.selected ||
    DossierState.locked => HETheme.pfGold,
    DossierState.resting => HETheme.pfSecondaryViolet,
    DossierState.unavailable => HETheme.pfTextMuted,
  };

  Color get _fill => switch (state) {
    DossierState.selected => const Color(0xFF2A2113),
    DossierState.available => const Color(0xFF241C0E),
    DossierState.locked => const Color(0xFF1B1508),
    DossierState.resting => HETheme.pfSurfaceRaised,
    DossierState.unavailable => HETheme.pfSurfaceDeep,
  };

  double get _borderW => switch (state) {
    DossierState.selected => 2.5,
    DossierState.available || DossierState.locked => 1.5,
    _ => 1.0,
  };

  String get _semanticLabel => switch (state) {
    DossierState.available => 'Sealed dossier $slotNumber, tap to choose',
    DossierState.selected => 'Sealed dossier $slotNumber, selected',
    DossierState.locked => 'Sealed dossier $slotNumber, locked in',
    DossierState.unavailable => 'Dossier $slotNumber, already taken',
    DossierState.resting => 'Sealed dossier $slotNumber, contents unknown',
  };

  @override
  Widget build(BuildContext context) {
    final selected = state == DossierState.selected;

    return Semantics(
      button: _tappable,
      selected: selected,
      label: _semanticLabel,
      child: GestureDetector(
        onTap: _tappable ? onTap : null,
        child: ConstrainedBox(
          // 44x44 minimum touch target regardless of how small the rendered
          // card gets in a dense grid.
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: AnimatedScale(
            // Selection lifts the chosen dossier; everything else stays put.
            scale: selected ? 1.05 : 1.0,
            duration: HEMotion.select,
            curve: HEMotion.easeOut,
            child: AnimatedOpacity(
              // Non-selected dossiers dim once one is chosen — handled by the
              // caller passing `resting` to the others.
              opacity: state == DossierState.unavailable ? 0.55 : 1.0,
              duration: HEMotion.select,
              child: AnimatedContainer(
                duration: HEMotion.focus,
                curve: HEMotion.easeOut,
                decoration: BoxDecoration(
                  boxShadow: _lit
                      ? [
                          BoxShadow(
                            color: _accent.withValues(
                              alpha: selected ? 0.38 : 0.22,
                            ),
                            blurRadius: selected ? 22 : 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: ClipPath(
                  clipper: const DossierFolderClip(),
                  child: CustomPaint(
                    painter: DossierFolderPainter(
                      fill: _fill,
                      accent: _accent,
                      borderWidth: _borderW,
                      showLavenderRim: selected,
                    ),
                    child: LayoutBuilder(
                      builder: (context, box) => _face(box.maxWidth),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _face(double w) {
    final locked = state == DossierState.locked;
    return Padding(
      padding: EdgeInsets.only(top: w * 0.12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Seal(accent: _accent, size: w * 0.34, closed: locked, lit: _lit),
          SizedBox(height: w * 0.08),
          Text(
            locked ? 'SEALED' : 'DOSSIER $slotNumber',
            style: HETheme.mono(
              size: (w * 0.115).clamp(8.0, 11.5),
              weight: FontWeight.w800,
              color: _lit ? _accent : HETheme.pfTextMuted,
            ).copyWith(letterSpacing: 0.6),
          ),
          if (state == DossierState.available) ...[
            SizedBox(height: w * 0.05),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: w * 0.08,
                vertical: w * 0.02,
              ),
              decoration: BoxDecoration(
                color: HETheme.pfGold.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(HEShape.rPill),
                border: Border.all(
                  color: HETheme.pfGold.withValues(alpha: 0.45),
                ),
              ),
              child: Text(
                'TAP TO CHOOSE',
                style: HETheme.displayLabel(
                  size: (w * 0.08).clamp(6.5, 9.5),
                  color: HETheme.pfGold,
                ).copyWith(letterSpacing: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The wax seal at the dossier's centre. Closes (ring → padlock) on lock —
/// the "seal-close interaction".
class _Seal extends StatelessWidget {
  const _Seal({
    required this.accent,
    required this.size,
    required this.closed,
    required this.lit,
  });

  final Color accent;
  final double size;
  final bool closed;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedSwitcher(
        duration: HEMotion.confirm,
        switchInCurve: HEMotion.overshoot,
        transitionBuilder: (child, anim) => ScaleTransition(
          scale: anim,
          child: FadeTransition(opacity: anim, child: child),
        ),
        child: closed
            ? Container(
                key: const ValueKey('closed'),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.16),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.75),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.lock_rounded,
                  color: accent,
                  size: size * 0.5,
                ),
              )
            : Container(
                key: const ValueKey('open'),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: accent.withValues(alpha: lit ? 0.85 : 0.45),
                    width: 1.5,
                  ),
                ),
                // The crest: a simple diamond, matching the pattern motif.
                child: Center(
                  child: Transform.rotate(
                    angle: 0.785398, // 45°
                    child: Container(
                      width: size * 0.30,
                      height: size * 0.30,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: lit ? 0.85 : 0.40),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// Cuts the file-folder silhouette: a raised tab on the top-left edge, the
/// rest rounded. This is what makes a dossier read as a *file* rather than as
/// a generic card back.
class DossierFolderClip extends CustomClipper<Path> {
  const DossierFolderClip();

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final r = (w * 0.12).clamp(6.0, 14.0);
    // Tab occupies the left ~42% of the top edge, stepping down by `notch`.
    final tabW = w * 0.42;
    final notch = (h * 0.07).clamp(5.0, 11.0);

    return Path()
      ..moveTo(0, r + notch)
      ..arcToPoint(Offset(r, notch), radius: Radius.circular(r))
      ..lineTo(tabW - notch, notch)
      ..lineTo(tabW + notch * 0.4, 0)
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
      ..lineTo(w, h - r)
      ..arcToPoint(Offset(w - r, h), radius: Radius.circular(r))
      ..lineTo(r, h)
      ..arcToPoint(Offset(0, h - r), radius: Radius.circular(r))
      ..close();
  }

  @override
  bool shouldReclip(DossierFolderClip oldClipper) => false;
}

/// Fills the folder shape, strokes its edge, and lays the decorative diamond
/// pattern over it. Parameterised by colour only — identical geometry for
/// every dossier regardless of contents.
class DossierFolderPainter extends CustomPainter {
  const DossierFolderPainter({
    required this.fill,
    required this.accent,
    required this.borderWidth,
    required this.showLavenderRim,
  });

  final Color fill;
  final Color accent;
  final double borderWidth;

  /// The selected state's second, inner rim — lavender over gold, so the
  /// chosen dossier is unmistakable without another glow.
  final bool showLavenderRim;

  @override
  void paint(Canvas canvas, Size size) {
    final path = const DossierFolderClip().getClip(size);

    // Body — a soft vertical gradient rather than a flat fill, so the folder
    // has depth before any pattern is drawn.
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(Colors.white.withValues(alpha: 0.045), fill),
            fill,
          ],
        ).createShader(Offset.zero & size),
    );

    _paintPattern(canvas, size, path);

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..color = accent.withValues(alpha: 0.85),
    );

    if (showLavenderRim) {
      canvas.save();
      canvas.scale(0.965);
      canvas.translate(size.width * 0.018, size.height * 0.018);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = HETheme.pfLavenderText.withValues(alpha: 0.55),
      );
      canvas.restore();
    }
  }

  /// Decorative diamond lattice — same geometry as the original
  /// `_DossierPatternPainter`, retained so the dossier keeps its texture.
  void _paintPattern(Canvas canvas, Size size, Path clip) {
    canvas.save();
    canvas.clipPath(clip);

    final spacing = size.width * 0.18;
    final paint = Paint()
      ..color = accent.withValues(alpha: 0.07)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (double y = -spacing; y < size.height + spacing; y += spacing) {
      final diamond = Path()
        ..moveTo(0, y + spacing / 2)
        ..lineTo(spacing / 2, y)
        ..lineTo(spacing, y + spacing / 2)
        ..lineTo(spacing / 2, y + spacing)
        ..close();
      for (double x = -spacing; x < size.width + spacing; x += spacing) {
        canvas.drawPath(diamond.shift(Offset(x, 0)), paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(DossierFolderPainter old) =>
      old.fill != fill ||
      old.accent != accent ||
      old.borderWidth != borderWidth ||
      old.showLavenderRim != showLavenderRim;
}
