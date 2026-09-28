import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:hidden_eleven/app/config.dart';

/// The ability cards. Mirrors the server `AbilityType` string union.
///
/// `protect` and `freeze` resolve under a fixed priority — freeze beats
/// protect beats everything else — because activation is simultaneous and
/// hidden, so there is no turn-based priority window to lean on instead. See
/// the server's `ability-resolution.ts` for the authoritative rules; the
/// client never re-derives them, only displays what the server reveals.
enum AbilityType { captain, yellow, red, extraBench, sub, coach, protect, freeze }

AbilityType? abilityTypeFromString(String? s) => switch (s) {
  'captain' => AbilityType.captain,
  'yellow' => AbilityType.yellow,
  'red' => AbilityType.red,
  'extra_bench' => AbilityType.extraBench,
  'sub' => AbilityType.sub,
  'coach' => AbilityType.coach,
  'protect' => AbilityType.protect,
  'freeze' => AbilityType.freeze,
  _ => null,
};

/// The wire value the server expects back for this type — the inverse of
/// [abilityTypeFromString]. Needed once a client action (activating an
/// ability) has to name its own type in an outgoing payload.
String abilityTypeToWire(AbilityType type) => switch (type) {
  AbilityType.captain => 'captain',
  AbilityType.yellow => 'yellow',
  AbilityType.red => 'red',
  AbilityType.extraBench => 'extra_bench',
  AbilityType.sub => 'sub',
  AbilityType.coach => 'coach',
  AbilityType.protect => 'protect',
  AbilityType.freeze => 'freeze',
};

/// Display identity (name, description, colour, icon) for each ability card.
/// `name`/`description`/`color` are admin-configurable server-side (see
/// AdminAbility on the server) — `icon` stays code-only (no server field for
/// it; see ensureLoaded's doc comment). `description` may contain chemistry
/// placeholders like `{yellowPenalty}` — resolve it through
/// ChemistryVars.resolve(...) before displaying it to a player.
class AbilityMeta {
  const AbilityMeta({
    required this.name,
    required this.description,
    required this.color,
    required this.icon,
  });

  final String name;
  final String description;
  final Color color;
  final IconData icon;

  /// Built-in fallback set — used before ensureLoaded() completes, or if the
  /// fetch ever fails. Mirrors the server's seedAbilities() defaults
  /// (admin.service.ts) at the time this was written; drifts only cosmetically
  /// if an admin edits the live values, since this is only ever shown for the
  /// few seconds before a successful fetch resolves, or on a genuine outage.
  static const _table = <AbilityType, AbilityMeta>{
    AbilityType.captain: AbilityMeta(
      name: 'Captain Card',
      description: 'Your captained player’s chemistry counts double.',
      color: Color(0xFFFFC83D),
      icon: Icons.shield_rounded,
    ),
    AbilityType.yellow: AbilityMeta(
      name: 'Yellow Card',
      description: 'Knock 20 points off a rival’s score.',
      color: Color(0xFFF2C037),
      icon: Icons.style_rounded,
    ),
    AbilityType.red: AbilityMeta(
      name: 'Red Card',
      description: 'Kill a rival player’s chemistry (rating stays).',
      color: Color(0xFFE74C3C),
      icon: Icons.do_not_disturb_on_rounded,
    ),
    AbilityType.extraBench: AbilityMeta(
      name: 'Extra Bench Card',
      description: 'An extra sub that fits ANY position.',
      color: Color(0xFF22D3EE),
      icon: Icons.event_seat_rounded,
    ),
    AbilityType.sub: AbilityMeta(
      name: 'Sub Card',
      description: 'Swap a player with a rival’s same-position player.',
      color: Color(0xFF2ECC71),
      icon: Icons.swap_horiz_rounded,
    ),
    AbilityType.coach: AbilityMeta(
      name: 'Coach Card',
      description: 'Add a new position to one of your players.',
      color: Color(0xFFA55CFF),
      // Every icon tried for Coach so far (sports_rounded, add_location_
      // alt_rounded, assignment_rounded, fact_check_rounded) rendered as a
      // blank circle for the user, even though each is a real, present-in-SDK
      // glyph — but all 4 were newly referenced by THIS feature and never
      // used anywhere else in the app before. Icons.insights_rounded is
      // reused here specifically because it's already actively rendered
      // elsewhere in this exact app (scoring_panel.dart's live chemistry
      // preview, a screen the player already sees every game) — if a
      // deployed build's icon-font subset was tree-shaken/cached BEFORE
      // Coach was added, only glyphs already reachable from pre-existing
      // code would have survived that subsetting, which this one is
      // guaranteed to. Reads as "insight/strategy" — a reasonable coaching
      // read — and, more importantly, is the one glyph in this file we can
      // be highly confident isn't blocked by that class of bug.
      icon: Icons.insights_rounded,
    ),
    AbilityType.protect: AbilityMeta(
      name: 'Protection',
      description: 'Shields you from every hostile ability this round — '
          'unless someone freezes you first.',
      color: Color(0xFF4FD1C5),
      icon: Icons.health_and_safety_rounded,
    ),
    AbilityType.freeze: AbilityMeta(
      name: 'Freeze',
      description: 'Disable a rival’s ability entirely — even Protection.',
      color: Color(0xFF63B3ED),
      icon: Icons.ac_unit_rounded,
    ),
  };

  // Admin-configured name/description/color, keyed by type. Null until
  // loaded; falls back to _table's built-in entries above — same
  // fetch-once-then-cache shape as CardTier._configured/ensureLoaded
  // (card_details_modal.dart). icon is never part of this — there's no
  // server field for it (out of scope; see the design spec's §8).
  static Map<AbilityType, ({String name, String description, Color color})>?
  _configured;

  /// Fetches the admin ability config once. Safe to call repeatedly.
  static Future<void> ensureLoaded() async {
    if (_configured != null) return;
    try {
      final res = await http
          .get(
            Uri.parse('${AppConfig.httpBase}/api/admin/abilities'),
            headers: {'ngrok-skip-browser-warning': 'true'},
          )
          // An unreachable host can otherwise hang on the OS-level connection
          // timeout (tens of seconds) before the catch below ever runs — see
          // the identical fix/rationale on ChemistryVars.ensureLoaded.
          .timeout(const Duration(seconds: 5));
      if (res.statusCode >= 300) return;
      final data = jsonDecode(res.body) as List<dynamic>;
      final configured =
          <AbilityType, ({String name, String description, Color color})>{};
      for (final e in data) {
        final m = e as Map<String, dynamic>;
        final type = abilityTypeFromString(m['type'] as String?);
        if (type == null) continue;
        final base = _table[type]!;
        final name = (m['name'] as String?)?.trim();
        final description = (m['description'] as String?)?.trim();
        final hex = m['color'] as String?;
        configured[type] = (
          name: (name != null && name.isNotEmpty) ? name : base.name,
          description: (description != null && description.isNotEmpty)
              ? description
              : base.description,
          color: hex != null ? _parseHex(hex) : base.color,
        );
      }
      if (configured.isNotEmpty) _configured = configured;
    } catch (_) {
      // keep built-in defaults
    }
  }

  static Color _parseHex(String hex) {
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    return Color(int.tryParse(h, radix: 16) ?? 0xFFB0BDD8);
  }

  /// Test-only seam: no HTTP-mocking precedent exists for this fetch-once
  /// pattern (see ChemistryVars.debugOverrideValues for the identical
  /// rationale), so tests simulate a "loaded" state directly. Pass null to
  /// reset back to "not yet loaded" (fallback _table values).
  @visibleForTesting
  static void debugOverrideConfigured(
    Map<AbilityType, ({String name, String description, Color color})>?
    configured,
  ) {
    _configured = configured;
  }

  /// The base (fallback) entry, with name/description/colour swapped for the
  /// admin-configured ones once ensureLoaded() has resolved. Before that (or
  /// if the fetch failed/returned nothing), the built-in _table entry is
  /// used unchanged — this never throws or returns a blank card. `icon`
  /// always comes from _table; there's no server-configured icon.
  static AbilityMeta of(AbilityType type) {
    final base = _table[type]!;
    final configured = _configured?[type];
    if (configured == null) return base;
    return AbilityMeta(
      name: configured.name,
      description: configured.description,
      color: configured.color,
      icon: base.icon,
    );
  }
}

/// One face-down (or revealed-to-me) card in the ability-draft pool.
@immutable
class AbilityCardInfo {
  const AbilityCardInfo({required this.id, this.pickedBy, this.type});

  final int id;

  /// Player id who picked this card, or null while face-down.
  final String? pickedBy;

  /// The ability type — non-null ONLY for the local player's own picked card.
  final AbilityType? type;

  bool get isPicked => pickedBy != null;
}

/// Snapshot of the turn-order ability draft, present only during `ability_draft`.
@immutable
class AbilityDraftState {
  const AbilityDraftState({
    required this.poolCount,
    required this.pickOrder,
    required this.currentPickIndex,
    required this.currentPickerId,
    required this.cards,
  });

  final int poolCount;
  final List<String> pickOrder;
  final int currentPickIndex;
  final String? currentPickerId;
  final List<AbilityCardInfo> cards;
}

/// The local player's own chosen ability (private) and its lifecycle.
@immutable
class PlayerAbility {
  const PlayerAbility({
    required this.type,
    required this.status,
    this.pendingSummary,
  });

  final AbilityType type;
  final String status; // 'pending' | 'used' | 'discarded'

  /// Plain-language description of what this ability WILL do, frozen by the
  /// server the moment it's committed (e.g. "Captain on Van de Ven"). Only
  /// ever present for the local player's own ability (via `myAbility`) — it
  /// stays private until the server's reveal pass publishes it to everyone
  /// via `abilityActivations`. Lets the "locked, waiting" UI show the player
  /// a reminder of their own choice without needing to re-derive it.
  final String? pendingSummary;

  bool get isPending => status == 'pending';
}

/// A publicly-announced ability activation (shown to all players).
@immutable
class AbilityActivation {
  const AbilityActivation({
    required this.byPlayerId,
    required this.byName,
    required this.type,
    required this.summary,
    this.targetUserId,
    this.targetSlotIndex,
  });

  final String byPlayerId;
  final String byName;
  final AbilityType type;
  final String summary;

  /// Targeted user (red/yellow/sub) — for computing live red-card impact.
  final String? targetUserId;

  /// Targeted slot in the rival's lineup (red/sub).
  final int? targetSlotIndex;
}
