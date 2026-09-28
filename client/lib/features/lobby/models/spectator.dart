import 'package:flutter/foundation.dart';

/// A read-only room observer — deliberately a separate model from [Player],
/// mirroring the server's Spectator/Player split (see
/// MULTIPLAYER_ROOMS_DESIGN.md). A spectator never has gameplay state (no
/// pitch, no turn order membership), so this stays intentionally minimal —
/// just enough to render a spectator list.
@immutable
class Spectator {
  const Spectator({
    required this.id,
    required this.displayName,
    this.isConnected = true,
  });

  final String id;
  final String displayName;
  final bool isConnected;
}
