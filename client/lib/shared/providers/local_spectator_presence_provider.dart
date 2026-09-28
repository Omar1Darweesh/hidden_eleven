import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hidden_eleven/services/local_spectator_presence_service.dart';

/// Mirrors local_presence_provider.dart's shape exactly, on a completely
/// separate provider/service pair — see LocalSpectatorPresenceData's
/// docstring for why that separation matters.
final localSpectatorPresenceServiceProvider =
    Provider<LocalSpectatorPresenceService>(
      (_) => LocalSpectatorPresenceService(),
    );

class LocalSpectatorPresenceNotifier
    extends Notifier<LocalSpectatorPresenceData?> {
  Completer<void>? _loadCompleter;

  /// Completes when the initial SharedPreferences load is done. Awaiting
  /// this guarantees [state] reflects the persisted value (or null) — same
  /// contract as LocalPresenceNotifier.ready.
  Future<void> get ready => _loadCompleter?.future ?? Future.value();

  @override
  LocalSpectatorPresenceData? build() {
    _loadCompleter = Completer<void>();
    _load();
    return null;
  }

  Future<void> _load() async {
    final data = await ref.read(localSpectatorPresenceServiceProvider).load();
    state = data;
    if (!_loadCompleter!.isCompleted) _loadCompleter!.complete();
  }

  Future<void> save(LocalSpectatorPresenceData data) async {
    await ref.read(localSpectatorPresenceServiceProvider).save(data);
    state = data;
  }

  Future<void> clear() async {
    await ref.read(localSpectatorPresenceServiceProvider).clear();
    state = null;
  }
}

final localSpectatorPresenceProvider =
    NotifierProvider<
      LocalSpectatorPresenceNotifier,
      LocalSpectatorPresenceData?
    >(LocalSpectatorPresenceNotifier.new);
