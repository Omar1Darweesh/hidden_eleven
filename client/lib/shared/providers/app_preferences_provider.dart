import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Text-size options exposed in the Settings sheet. Values are multipliers
/// applied on top of the platform's own accessibility text scale (see
/// `app.dart`'s `MediaQuery` override) — never a replacement for it, so a
/// user who has also increased their OS-level text size keeps that on top
/// of whichever of these they pick.
enum TextScaleOption {
  standard(1.0, 'Standard'),
  large(1.15, 'Large'),
  xl(1.3, 'XL');

  const TextScaleOption(this.multiplier, this.label);
  final double multiplier;
  final String label;

  static TextScaleOption fromName(String? name) =>
      TextScaleOption.values.firstWhere(
        (o) => o.name == name,
        orElse: () => TextScaleOption.standard,
      );
}

/// App-wide, presentation-only preferences — deliberately separate from
/// [audioMutedProvider]'s pair of flags (which already had their own
/// persistence and providers before this) so this model stays focused on
/// the two NEW cross-cutting concerns: motion and text scale. Immutable and
/// trivially testable in isolation from any widget.
@immutable
class AppPreferences {
  const AppPreferences({
    this.reducedMotion = false,
    this.textScale = TextScaleOption.standard,
  });

  /// User's explicit override — combined with the OS-level
  /// `MediaQuery.disableAnimations` signal at the point of use (app.dart),
  /// never replacing it. Either source being true means motion is reduced.
  final bool reducedMotion;

  final TextScaleOption textScale;

  AppPreferences copyWith({bool? reducedMotion, TextScaleOption? textScale}) {
    return AppPreferences(
      reducedMotion: reducedMotion ?? this.reducedMotion,
      textScale: textScale ?? this.textScale,
    );
  }
}

/// Persistence boundary, isolated behind a small interface so a future swap
/// (e.g. syncing preferences server-side per account) doesn't require
/// touching the notifier or any UI. Backed by `shared_preferences` — already
/// a project dependency (see `audio_service.dart`), so this adds no new
/// package.
abstract class AppPreferencesRepository {
  Future<AppPreferences> load();
  Future<void> saveReducedMotion(bool value);
  Future<void> saveTextScale(TextScaleOption value);
}

const _reducedMotionKey = 'pref_reduced_motion';
const _textScaleKey = 'pref_text_scale';

class SharedPreferencesAppPreferencesRepository
    implements AppPreferencesRepository {
  @override
  Future<AppPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppPreferences(
      reducedMotion: prefs.getBool(_reducedMotionKey) ?? false,
      textScale: TextScaleOption.fromName(prefs.getString(_textScaleKey)),
    );
  }

  @override
  Future<void> saveReducedMotion(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reducedMotionKey, value);
  }

  @override
  Future<void> saveTextScale(TextScaleOption value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_textScaleKey, value.name);
  }
}

/// Swappable in tests via `ProviderScope(overrides: [
/// appPreferencesRepositoryProvider.overrideWithValue(FakeRepo())])` —
/// avoids every preferences test needing real `SharedPreferences` plumbing.
final appPreferencesRepositoryProvider = Provider<AppPreferencesRepository>(
  (ref) => SharedPreferencesAppPreferencesRepository(),
);

final appPreferencesProvider =
    NotifierProvider<AppPreferencesNotifier, AppPreferences>(
      AppPreferencesNotifier.new,
    );

class AppPreferencesNotifier extends Notifier<AppPreferences> {
  @override
  AppPreferences build() {
    // Fire-and-forget, same pattern as AudioService's muted flags: the
    // persisted value (if any) arrives a moment later, and the in-memory
    // default here is the correct value for that first frame regardless.
    _loadPersisted();
    return const AppPreferences();
  }

  Future<void> _loadPersisted() async {
    final loaded = await ref.read(appPreferencesRepositoryProvider).load();
    state = loaded;
  }

  Future<void> setReducedMotion(bool value) async {
    if (state.reducedMotion == value) return;
    state = state.copyWith(reducedMotion: value);
    await ref.read(appPreferencesRepositoryProvider).saveReducedMotion(value);
  }

  Future<void> setTextScale(TextScaleOption value) async {
    if (state.textScale == value) return;
    state = state.copyWith(textScale: value);
    await ref.read(appPreferencesRepositoryProvider).saveTextScale(value);
  }
}
