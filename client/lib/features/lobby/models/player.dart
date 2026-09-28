import 'package:flutter/foundation.dart';

@immutable
class Player {
  const Player({
    required this.id,
    required this.displayName,
    required this.isHost,
    this.isConnected = true,
    this.isWaiting = false,
    this.isBot = false,
  });

  final String id;
  final String displayName;
  final bool isHost;
  final bool isConnected;
  final bool isWaiting;

  /// A server-driven AI opponent — see solo-mode's BotService. Lets the
  /// lobby badge a bot seat distinctly from a real, possibly-still-loading
  /// human player.
  final bool isBot;

  Player copyWith({
    String? displayName,
    bool? isHost,
    bool? isConnected,
    bool? isWaiting,
    bool? isBot,
  }) {
    return Player(
      id: id,
      displayName: displayName ?? this.displayName,
      isHost: isHost ?? this.isHost,
      isConnected: isConnected ?? this.isConnected,
      isWaiting: isWaiting ?? this.isWaiting,
      isBot: isBot ?? this.isBot,
    );
  }
}
