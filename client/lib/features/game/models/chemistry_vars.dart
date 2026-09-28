import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:hidden_eleven/app/config.dart';

/// Chemistry-related admin-configurable numbers, exposed to UI text via
/// named `{placeholder}` tokens (e.g. "+{lineLeaderBonus} per line"). The
/// server's published scoring-config (see hidden_eleven_server's
/// scoring-config.ts) is the single source of truth — this class only
/// fetches and caches it for TEXT interpolation; it has no bearing on
/// actual scoring math, which is computed and snapshotted server-side.
///
/// [resolve] is used both by fixed code templates (gameplay screens) and by
/// admin-authored free text (guide pages, FAQ, quick tips, context-help,
/// ability descriptions) — [findUnknownPlaceholders] backs the admin
/// dashboard's non-blocking "unknown placeholder" save-time warning.
class ChemistryVars {
  ChemistryVars._();

  /// v1 defaults — mirrors DEFAULT_SCORING_CONFIG_V1 (scoring-config.ts)
  /// exactly. Used both before ensureLoaded() completes and if the fetch
  /// ever fails, so resolve() never shows a player a raw "{token}".
  static const Map<String, int> _fallbackValues = {
    'challengeReward': 5,
    'tierEasyReward': 2,
    'tierMediumReward': 4,
    'tierHardReward': 6,
    'lineLeaderBonus': 2,
    'yellowPenalty': 20,
    'captainMultiplier': 2,
  };

  /// Shown in place of an unrecognized `{token}` — never the raw token
  /// text, never a crash.
  static const String _unknownPlaceholderMarker = '—';

  // Admin-configured values, fetched once. Null until loaded — same
  // fetch-once-then-cache shape as AbilityMeta._configuredColors/
  // ensureLoaded (ability.dart) and CardTier._configured/ensureLoaded
  // (card_details_modal.dart).
  static Map<String, int>? _configuredValues;

  /// Fetches the published scoring config once. Safe to call repeatedly.
  static Future<void> ensureLoaded() async {
    if (_configuredValues != null) return;
    try {
      final res = await http
          .get(
            Uri.parse(
              '${AppConfig.httpBase}/api/admin/scoring-config/published',
            ),
            headers: {'ngrok-skip-browser-warning': 'true'},
          )
          // An unreachable host can otherwise hang on the OS-level connection
          // timeout (tens of seconds) before the catch below ever runs — a
          // slow failure is still a failure, so cap it and swallow it promptly.
          .timeout(const Duration(seconds: 5));
      if (res.statusCode >= 300) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final values = data['values'] as Map<String, dynamic>?;
      if (values == null) return;
      final parsed = _flatten(values);
      if (parsed.isNotEmpty) _configuredValues = parsed;
    } catch (_) {
      // keep built-in fallback defaults
    }
  }

  /// Flattens the server's nested ScoringConfigValues shape into the flat
  /// name → value map resolve() reads. Missing/malformed sub-objects are
  /// tolerated field-by-field — a malformed piece of the response doesn't
  /// discard values that parsed fine.
  static Map<String, int> _flatten(Map<String, dynamic> values) {
    final userChallenges = values['userChallenges'] as Map<String, dynamic>?;
    final cardChemistry = values['cardChemistry'] as Map<String, dynamic>?;
    final tierRewards = cardChemistry?['tierRewards'] as Map<String, dynamic>?;
    final lineLeader = values['lineLeader'] as Map<String, dynamic>?;
    final abilityEffects = values['abilityEffects'] as Map<String, dynamic>?;

    final out = <String, int>{};
    void put(String key, dynamic raw) {
      if (raw is num) out[key] = raw.toInt();
    }

    put('challengeReward', userChallenges?['rewardPerChallenge']);
    put('tierEasyReward', tierRewards?['easy']);
    put('tierMediumReward', tierRewards?['medium']);
    put('tierHardReward', tierRewards?['hard']);
    put('lineLeaderBonus', lineLeader?['bonusPerLine']);
    put('yellowPenalty', abilityEffects?['yellowPenalty']);
    put('captainMultiplier', abilityEffects?['captainMultiplier']);
    return out;
  }

  static final RegExp _placeholderPattern = RegExp(r'\{(\w+)\}');

  /// Resolves every `{name}` token in [template] against the currently
  /// loaded (or fallback) chemistry values. Never throws. A name that
  /// isn't one of the known chemistry variables is left as a small marker
  /// rather than the raw `{token}` text.
  static String resolve(String template) {
    return template.replaceAllMapped(_placeholderPattern, (match) {
      final name = match.group(1)!;
      final value =
          (_configuredValues ?? const {})[name] ?? _fallbackValues[name];
      return value != null ? '$value' : _unknownPlaceholderMarker;
    });
  }

  /// Every `{name}` token in [template] that resolve() would NOT be able to
  /// substitute — i.e. not one of the known chemistry variable names.
  /// Case-sensitive (the vocabulary is, deliberately — see resolve()).
  /// Returns names without braces, in the order they first appear, never
  /// duplicated. Used only for the admin dashboard's save-time warning
  /// (§D5) — resolve() itself never needs this, it already degrades unknown
  /// tokens safely on its own.
  static List<String> findUnknownPlaceholders(String template) {
    final seen = <String>{};
    final unknown = <String>[];
    for (final match in _placeholderPattern.allMatches(template)) {
      final name = match.group(1)!;
      if (_fallbackValues.containsKey(name)) continue;
      if (seen.add(name)) unknown.add(name);
    }
    return unknown;
  }

  /// Test-only seam: this codebase has no existing HTTP-mocking precedent
  /// for the fetch-once-cache pattern ensureLoaded() follows, so tests
  /// simulate a "loaded" state directly instead. Pass null to reset back
  /// to "not yet loaded" (fallback values).
  @visibleForTesting
  static void debugOverrideValues(Map<String, int>? values) {
    _configuredValues = values;
  }
}
