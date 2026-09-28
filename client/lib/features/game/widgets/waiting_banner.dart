import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';


/// The one "nothing to do yet, here's who we're waiting on" state, shared
/// across every phase that needs it (first_player_order, hidden_pick,
/// end-of-branch fallback) instead of each screen defining its own
/// near-identical box with a spinner. Renders bare — no border/background of
/// its own — since it always renders inside GameActionSheet, which already
/// supplies the one frame around the sheet's content.
class WaitingBanner extends StatelessWidget {
  const WaitingBanner({super.key, required this.message});

  /// Full sentence to show, e.g. "Waiting for Alice…" or
  /// "Waiting for Alice to order the cards…".
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: HETheme.pfTextSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: HETheme.pfTextSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
