import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hidden_eleven/services/local_presence_service.dart';

final localPresenceServiceProvider = Provider<LocalPresenceService>(
  (_) => LocalPresenceService(),
);

class LocalPresenceNotifier extends Notifier<LocalPresenceData?> {
  Completer<void>? _loadCompleter;

  /// Completes when the initial SharedPreferences load is done.
  /// Awaiting this guarantees [state] reflects the persisted value (or null).
  Future<void> get ready => _loadCompleter?.future ?? Future.value();

  @override
  LocalPresenceData? build() {
    _loadCompleter = Completer<void>();
    _load();
    return null;
  }

  Future<void> _load() async {
    final data = await ref.read(localPresenceServiceProvider).load();
    state = data;
    if (!_loadCompleter!.isCompleted) _loadCompleter!.complete();
  }

  Future<void> save(LocalPresenceData data) async {
    await ref.read(localPresenceServiceProvider).save(data);
    state = data;
  }

  Future<void> updateStatus(LocalPresenceStatus status) async {
    final current = state;
    if (current == null) return;
    await ref.read(localPresenceServiceProvider).updateStatus(status);
    state = LocalPresenceData(
      playerId: current.playerId,
      roomCode: current.roomCode,
      displayName: current.displayName,
      status: status,
      reconnectToken: current.reconnectToken,
    );
  }

  Future<void> clear() async {
    await ref.read(localPresenceServiceProvider).clear();
    state = null;
  }
}

final localPresenceProvider =
    NotifierProvider<LocalPresenceNotifier, LocalPresenceData?>(
      LocalPresenceNotifier.new,
    );
