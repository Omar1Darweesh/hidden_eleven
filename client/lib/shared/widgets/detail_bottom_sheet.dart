import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';

/// Opens [child] in a draggable bottom sheet with the shared "secondary
/// detail" chrome (rounded top, drag handle, elevated surface) — the one
/// place non-critical detail (full scoring breakdown, unpicked cards, etc.)
/// expands into when a player taps its compact summary/chip, instead of
/// each screen inventing its own sheet wrapper.
Future<void> showDetailBottomSheet(
  BuildContext context, {
  required Widget child,
  double initialChildSize = 0.55,
  double minChildSize = 0.3,
  double maxChildSize = 0.9,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: initialChildSize,
      minChildSize: minChildSize,
      maxChildSize: maxChildSize,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: const BoxDecoration(
          color: HETheme.pfSurfaceGlass,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: HETheme.pfBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                child: child,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
