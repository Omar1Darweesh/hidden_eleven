import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _sfxMutedPrefsKey = 'sfx_muted';
const _musicMutedPrefsKey = 'music_muted';

/// Every one-shot sound effect the game plays. Each maps 1:1 to an asset
/// under `assets/sounds/` — see pubspec.yaml.
enum Sfx {
  pickCard('sounds/pick_card.mp3'),
  reveal('sounds/reveal.mp3'),
  timerTicker('sounds/timer_ticker.mp3'),
  abilityUse('sounds/ability_use.ogg'),
  invalidAction('sounds/invalid_action.ogg'),
  notification('sounds/notification.ogg'),
  victory('sounds/victory.ogg'),
  defeat('sounds/defeat.ogg'),
  buttonTap('sounds/button_tap.ogg'),
  cardDeal('sounds/card_deal.ogg'),
  timerWarning('sounds/timer_warning.ogg');

  const Sfx(this.assetPath);
  final String assetPath;
}

/// Base for the two independent mute flags below — same persisted-toggle
/// shape, differing only in which prefs key they use.
///
/// Deliberately does NOT push its new value into [AudioService] itself —
/// [audioServiceProvider]'s own `ref.listen` on both flags already does
/// that for every change, once it has been built. Having this notifier
/// ALSO reach into `ref.read(audioServiceProvider)` directly would create a
/// real circular dependency: `audioServiceProvider`'s build reads these
/// flags to seed its initial state, so a flag's own notifier reading
/// `audioServiceProvider` back closes the cycle. It stayed dormant in the
/// app (something always reads `audioServiceProvider` — and so builds it —
/// before any toggle can happen) but broke immediately in a fresh
/// `ProviderContainer` with no prior reads, which is exactly the shape a
/// unit test uses. Removing the direct call breaks the cycle with no loss
/// of behavior: `audioServiceProvider`, once built, still reacts to every
/// future change via its own listeners.
abstract class _MutedNotifier extends Notifier<bool> {
  String get _prefsKey;

  @override
  bool build() {
    // Fire-and-forget: the real persisted value (if any) arrives a moment
    // later via _loadPersisted. Starting unmuted is the correct default even
    // for that first frame — a silent game is what prompted adding sound in
    // the first place, so the player opts out, not in.
    _loadPersisted();
    return false;
  }

  Future<void> _loadPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getBool(_prefsKey);
    if (stored != null) state = stored;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, state);
  }

  Future<void> setValue(bool muted) async {
    if (state == muted) return;
    state = muted;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, state);
  }
}

/// Sound-effects mute — pick/reveal/timer cues. Independent of [musicMutedProvider].
final sfxMutedProvider = NotifierProvider<SfxMutedNotifier, bool>(
  SfxMutedNotifier.new,
);

class SfxMutedNotifier extends _MutedNotifier {
  @override
  String get _prefsKey => _sfxMutedPrefsKey;
}

/// Background/menu music mute. Independent of [sfxMutedProvider].
final musicMutedProvider = NotifierProvider<MusicMutedNotifier, bool>(
  MusicMutedNotifier.new,
);

class MusicMutedNotifier extends _MutedNotifier {
  @override
  String get _prefsKey => _musicMutedPrefsKey;
}

/// Single "mute everything" convenience — the home screen's one speaker
/// icon predates the Settings sheet's separate SFX/Music toggles and keeps
/// its exact existing behavior (one tap silences both, tap again restores
/// both) by driving [sfxMutedProvider] and [musicMutedProvider] together
/// rather than owning independent state of its own. Reads as "muted" only
/// when both underlying flags are already true, so it never contradicts
/// what the Settings sheet shows.
final audioMutedProvider = Provider<bool>((ref) {
  final sfx = ref.watch(sfxMutedProvider);
  final music = ref.watch(musicMutedProvider);
  return sfx && music;
});

/// Toggles both [sfxMutedProvider] and [musicMutedProvider] together — the
/// action behind the home screen's single speaker icon.
Future<void> toggleAllAudioMuted(WidgetRef ref) async {
  final target = !ref.read(audioMutedProvider);
  await ref.read(sfxMutedProvider.notifier).setValue(target);
  await ref.read(musicMutedProvider.notifier).setValue(target);
}

final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AudioService();
  ref.onDispose(service.dispose);
  // Keep the service's two independent flags in sync with their persisted
  // providers, including each provider's async load resolving after this
  // provider is first read.
  ref.listen<bool>(sfxMutedProvider, (_, muted) => service.setSfxMuted(muted));
  ref.listen<bool>(
    musicMutedProvider,
    (_, muted) => service.setMusicMuted(muted),
  );
  service.setSfxMuted(ref.read(sfxMutedProvider));
  service.setMusicMuted(ref.read(musicMutedProvider));
  return service;
});

/// Thin wrapper around audioplayers for the game's sound effects and
/// background music. Two concerns kept deliberately separate:
///
/// - SFX: short one-shots (pick, reveal, timer). Each gets its own
///   [AudioPlayer] instance so overlapping triggers (e.g. two quick picks)
///   don't cut each other off — `audioplayers` serializes playback on a
///   single player instance otherwise.
/// - Music: one long-lived looping player, independently volume-controlled
///   and quieter than SFX so it never competes with gameplay cues.
class AudioService {
  final Map<Sfx, AudioPlayer> _sfxPlayers = {
    for (final sfx in Sfx.values) sfx: AudioPlayer(playerId: 'sfx_${sfx.name}'),
  };
  final AudioPlayer _music = AudioPlayer(playerId: 'menu_music');

  bool _sfxMuted = false;
  bool _musicMuted = false;
  bool _musicWanted = false;

  static const _musicVolume = 0.35;

  AudioService() {
    // Manual loop instead of ReleaseMode.loop: on this app's web backend,
    // the built-in loop mode was audibly speeding the track up on repeat
    // (likely restarting fractionally before the previous cycle's audio
    // buffer had actually finished draining). Seeking to zero and resuming
    // ourselves, only once the track has genuinely completed, avoids that
    // entirely and gives an ordinary, correctly-paced loop.
    _music.onPlayerComplete.listen((_) {
      if (_musicWanted && !_musicMuted) {
        _guardAsync(() async {
          await _music.seek(Duration.zero);
          await _music.resume();
        });
      }
    });
  }

  void setSfxMuted(bool muted) => _sfxMuted = muted;

  void setMusicMuted(bool muted) {
    _musicMuted = muted;
    // Every entry point below is wrapped: audio is a nice-to-have layered on
    // top of the actual game, and audioplayers' web backend has already
    // shown real gaps (see the pubspec.yaml note on the 5.2.1 pin) — nothing
    // it does is allowed to take the app down with it.
    _guard(() {
      // The hard guarantee: forcing volume to 0 works even when pause()
      // doesn't. Chrome's autoplay policy can DEFER a blocked play() call
      // (from the very first, pre-interaction playMenuMusic attempt) and
      // silently fire it later on the user's first click, completely
      // bypassing whatever pause()/resume() calls happened in between —
      // a real race that was observed muting the icon while the deferred
      // track kept playing regardless. Volume is a property of the
      // underlying element, not a play-state transition, so it can't lose
      // that race the way pause()/resume() can.
      _music.setVolume(muted ? 0 : _musicVolume);
      if (muted) {
        _music.pause();
      } else if (_musicWanted) {
        _music.resume();
      }
    });
  }

  Future<void> playSfx(Sfx sfx) async {
    if (_sfxMuted) return;
    await _guardAsync(() async {
      final player = _sfxPlayers[sfx]!;
      // stop+play rather than seek(0)+resume: a rapid re-trigger (e.g.
      // picking two cards back to back) must restart cleanly, and stop() is
      // the reliable way to do that across audioplayers' web/native backends.
      await player.stop();
      await player.play(AssetSource(sfx.assetPath), volume: 1.0);
    });
  }

  /// Starts the looping menu/ambient track. Safe to call repeatedly (e.g. on
  /// every home-screen build) — it no-ops if already playing.
  Future<void> playMenuMusic() async {
    _musicWanted = true;
    if (_musicMuted) return;
    await _guardAsync(() async {
      if (_music.state == PlayerState.playing) return;
      // ReleaseMode.stop (not .loop) — see the constructor's onPlayerComplete
      // listener, which drives the actual repeat.
      await _music.setReleaseMode(ReleaseMode.stop);
      await _music.play(
        AssetSource('sounds/menue.mp3'),
        volume: _musicMuted ? 0 : _musicVolume,
      );
    });
  }

  /// Stops the menu track — called when leaving to an active match, where
  /// background music would compete with gameplay SFX.
  Future<void> stopMenuMusic() async {
    _musicWanted = false;
    await _guardAsync(() => _music.stop());
  }

  void dispose() {
    _guard(() {
      for (final player in _sfxPlayers.values) {
        player.dispose();
      }
      _music.dispose();
    });
  }

  void _guard(void Function() body) {
    try {
      body();
    } catch (e, st) {
      // ignore: avoid_print
      print('AudioService error (ignored): $e\n$st');
    }
  }

  Future<void> _guardAsync(Future<void> Function() body) async {
    try {
      await body();
    } catch (e, st) {
      // ignore: avoid_print
      print('AudioService error (ignored): $e\n$st');
    }
  }
}
