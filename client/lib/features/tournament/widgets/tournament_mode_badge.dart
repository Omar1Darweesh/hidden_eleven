import 'package:flutter/material.dart';

/// A small badge shown in the lobby when tournament mode is enabled.
/// Returns SizedBox.shrink() when tournamentEnabled is false.
class TournamentModeBadge extends StatelessWidget {
  final bool tournamentEnabled;

  const TournamentModeBadge({super.key, required this.tournamentEnabled});

  @override
  Widget build(BuildContext context) {
    if (!tournamentEnabled) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B4332), Color(0xFF2D6A4F)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF4CAF50), width: 1),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.emoji_events, size: 13, color: Color(0xFF4CAF50)),
          SizedBox(width: 5),
          Text(
            'Tournament Mode',
            style: TextStyle(
              color: Color(0xFF4CAF50),
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
