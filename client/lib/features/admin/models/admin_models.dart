import 'package:flutter/foundation.dart';

// ── AdminBackupStatus ──────────────────────────────────────────────────────────
// Read-only mirror of BackupService's BackupStatus (backup.service.ts) — a
// single rotating archive (admin-data/ + assets/ + match-history.db),
// refreshed daily by a server-side cron job and/or on demand via "Backup
// Now". No history list: by design there is only ever one archive.

@immutable
class AdminBackupStatus {
  const AdminBackupStatus({
    required this.exists,
    this.filename,
    this.sizeBytes,
    this.createdAt,
  });

  final bool exists;
  final String? filename;
  final int? sizeBytes;
  final String? createdAt;

  factory AdminBackupStatus.fromJson(Map<String, dynamic> j) =>
      AdminBackupStatus(
        exists: j['exists'] as bool? ?? false,
        filename: j['filename'] as String?,
        sizeBytes: (j['sizeBytes'] as num?)?.toInt(),
        createdAt: j['createdAt'] as String?,
      );
}

// ── Positions ──────────────────────────────────────────────────────────────────

const kAllPositions = [
  'GK',
  'LB',
  'CB',
  'RB',
  'CDM',
  'CM',
  'CAM',
  'LM',
  'RM',
  'LW',
  'RW',
  'CF',
  'ST',
];

// ── AdminPlayer ────────────────────────────────────────────────────────────────

@immutable
class AdminPlayer {
  const AdminPlayer({
    required this.id,
    required this.name,
    required this.rating,
    required this.positions,
    required this.nationality,
    required this.club,
    this.photoUrl,
    this.photoLegalOverride = false,
    this.clubLogoUrl,
    this.kitNumber,
    this.league,
    this.pace,
    this.shooting,
    this.passing,
    this.dribbling,
    this.defending,
    this.physical,
  });

  final String id;
  final String name;
  final int rating;
  final List<String> positions;
  final String nationality;
  final String club;
  final String? photoUrl;
  // Manual admin confirmation that photoUrl is properly licensed — only
  // needed for sources the app can't verify automatically (e.g. an uploaded
  // file). See [players_tab.dart]'s _hasLegalPhoto for the full rule.
  final bool photoLegalOverride;
  final String? clubLogoUrl;
  // Shirt number shown on the jersey-back player card. Unset players get a
  // generated 1-99 number instead (deterministic per player, client-side).
  final int? kitNumber;
  final String? league;
  final int? pace;
  final int? shooting;
  final int? passing;
  final int? dribbling;
  final int? defending;
  final int? physical;

  String get primaryPosition => positions.isNotEmpty ? positions.first : '';
  List<String> get altPositions =>
      positions.length > 1 ? positions.sublist(1) : [];

  /// Stat name → value pairs, in display order. Null stats are omitted.
  List<({String label, int value})> get statBars => [
    if (pace != null) (label: 'PAC', value: pace!),
    if (shooting != null) (label: 'SHO', value: shooting!),
    if (passing != null) (label: 'PAS', value: passing!),
    if (dribbling != null) (label: 'DRI', value: dribbling!),
    if (defending != null) (label: 'DEF', value: defending!),
    if (physical != null) (label: 'PHY', value: physical!),
  ];

  static int? _toIntOrNull(dynamic v) => v == null ? null : (v as num).toInt();

  factory AdminPlayer.fromJson(Map<String, dynamic> j) => AdminPlayer(
    id: j['id'] as String,
    name: j['name'] as String,
    rating: (j['rating'] as num).toInt(),
    positions: (j['positions'] as List<dynamic>)
        .map((e) => e as String)
        .toList(),
    nationality: j['nationality'] as String? ?? '',
    club: j['club'] as String? ?? '',
    photoUrl: j['photoUrl'] as String?,
    photoLegalOverride: j['photoLegalOverride'] as bool? ?? false,
    clubLogoUrl: j['clubLogoUrl'] as String?,
    kitNumber: _toIntOrNull(j['kitNumber']),
    league: j['league'] as String?,
    pace: _toIntOrNull(j['pace']),
    shooting: _toIntOrNull(j['shooting']),
    passing: _toIntOrNull(j['passing']),
    dribbling: _toIntOrNull(j['dribbling']),
    defending: _toIntOrNull(j['defending']),
    physical: _toIntOrNull(j['physical']),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'rating': rating,
    'positions': positions,
    'nationality': nationality,
    'club': club,
    if (photoUrl != null) 'photoUrl': photoUrl,
    'photoLegalOverride': photoLegalOverride,
    if (clubLogoUrl != null) 'clubLogoUrl': clubLogoUrl,
    if (kitNumber != null) 'kitNumber': kitNumber,
    if (league != null) 'league': league,
    if (pace != null) 'pace': pace,
    if (shooting != null) 'shooting': shooting,
    if (passing != null) 'passing': passing,
    if (dribbling != null) 'dribbling': dribbling,
    if (defending != null) 'defending': defending,
    if (physical != null) 'physical': physical,
  };

  AdminPlayer copyWith({
    String? name,
    int? rating,
    List<String>? positions,
    String? nationality,
    String? club,
    String? photoUrl,
    bool? photoLegalOverride,
    String? clubLogoUrl,
    int? kitNumber,
    String? league,
    int? pace,
    int? shooting,
    int? passing,
    int? dribbling,
    int? defending,
    int? physical,
  }) => AdminPlayer(
    id: id,
    name: name ?? this.name,
    rating: rating ?? this.rating,
    positions: positions ?? this.positions,
    nationality: nationality ?? this.nationality,
    club: club ?? this.club,
    photoUrl: photoUrl ?? this.photoUrl,
    photoLegalOverride: photoLegalOverride ?? this.photoLegalOverride,
    clubLogoUrl: clubLogoUrl ?? this.clubLogoUrl,
    kitNumber: kitNumber ?? this.kitNumber,
    league: league ?? this.league,
    pace: pace ?? this.pace,
    shooting: shooting ?? this.shooting,
    passing: passing ?? this.passing,
    dribbling: dribbling ?? this.dribbling,
    defending: defending ?? this.defending,
    physical: physical ?? this.physical,
  );
}

// ── AdminClub ──────────────────────────────────────────────────────────────────

@immutable
class AdminClub {
  const AdminClub({
    required this.slug,
    required this.name,
    required this.league,
    this.logoUrl,
    this.primaryColor,
    this.secondaryColor,
    this.tertiaryColor,
    this.kitPattern,
    this.active = true,
    this.cardStyle,
  });

  final String slug;
  final String name;
  final String league;
  final String? logoUrl;
  // Kit colors (hex, e.g. "#0B1E3D") — drive the jersey-back player card
  // design in-game. Unset clubs fall back to a deterministic per-name color
  // client-side (see jersey_back.dart), so this is optional polish, not
  // required for every club to have a card.
  final String? primaryColor;
  final String? secondaryColor;
  // Collar and cuff trim; falls back to the secondary when unset.
  final String? tertiaryColor;
  // KitPattern's .name (e.g. "stripes") — unset clubs fall back to a
  // deterministic per-name pattern client-side, same as the colors above.
  final String? kitPattern;
  // "Allowed to play with or not" gate, same as AdminLeague.active — when
  // false every player from this club is excluded from every draft pool.
  final bool active;
  // Special card frame overriding the normal rating-tier band — 'icon'
  // (gold/brown) or 'hero' (blue/purple). Null/unrecognized = normal frame.
  // See CardTier.forCard (card_details_modal.dart).
  final String? cardStyle;

  factory AdminClub.fromJson(Map<String, dynamic> j) => AdminClub(
    slug: j['slug'] as String,
    name: j['name'] as String,
    league: j['league'] as String? ?? '',
    logoUrl: j['logoUrl'] as String?,
    primaryColor: j['primaryColor'] as String?,
    secondaryColor: j['secondaryColor'] as String?,
    tertiaryColor: j['tertiaryColor'] as String?,
    kitPattern: j['kitPattern'] as String?,
    active: j['active'] as bool? ?? true,
    cardStyle: j['cardStyle'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'league': league,
    if (logoUrl != null) 'logoUrl': logoUrl,
    if (primaryColor != null) 'primaryColor': primaryColor,
    if (secondaryColor != null) 'secondaryColor': secondaryColor,
    if (tertiaryColor != null) 'tertiaryColor': tertiaryColor,
    if (kitPattern != null) 'kitPattern': kitPattern,
    'active': active,
    if (cardStyle != null) 'cardStyle': cardStyle,
  };

  AdminClub copyWith({
    String? name,
    String? league,
    String? logoUrl,
    String? primaryColor,
    String? secondaryColor,
    String? tertiaryColor,
    String? kitPattern,
    bool? active,
    String? cardStyle,
  }) => AdminClub(
    slug: slug,
    name: name ?? this.name,
    league: league ?? this.league,
    logoUrl: logoUrl ?? this.logoUrl,
    primaryColor: primaryColor ?? this.primaryColor,
    secondaryColor: secondaryColor ?? this.secondaryColor,
    tertiaryColor: tertiaryColor ?? this.tertiaryColor,
    kitPattern: kitPattern ?? this.kitPattern,
    active: active ?? this.active,
    cardStyle: cardStyle ?? this.cardStyle,
  );
}

// ── AdminNation ────────────────────────────────────────────────────────────────

@immutable
class AdminNation {
  const AdminNation({required this.slug, required this.name, this.flagUrl});

  final String slug;
  final String name;
  final String? flagUrl;

  factory AdminNation.fromJson(Map<String, dynamic> j) => AdminNation(
    slug: j['slug'] as String,
    name: j['name'] as String,
    flagUrl: j['flagUrl'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    if (flagUrl != null) 'flagUrl': flagUrl,
  };

  AdminNation copyWith({String? name, String? flagUrl}) => AdminNation(
    slug: slug,
    name: name ?? this.name,
    flagUrl: flagUrl ?? this.flagUrl,
  );
}

// ── AdminLeague ────────────────────────────────────────────────────────────────

@immutable
class AdminLeague {
  const AdminLeague({
    required this.slug,
    required this.name,
    this.logoUrl,
    this.active = true,
  });

  final String slug;
  final String name;
  final String? logoUrl;
  final bool active;

  factory AdminLeague.fromJson(Map<String, dynamic> j) => AdminLeague(
    slug: j['slug'] as String,
    name: j['name'] as String,
    logoUrl: j['logoUrl'] as String?,
    active: j['active'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    if (logoUrl != null) 'logoUrl': logoUrl,
    'active': active,
  };

  AdminLeague copyWith({String? name, String? logoUrl, bool? active}) =>
      AdminLeague(
        slug: slug,
        name: name ?? this.name,
        logoUrl: logoUrl ?? this.logoUrl,
        active: active ?? this.active,
      );
}

// ── AdminLeagueBundle ──────────────────────────────────────────────────────────

@immutable
class AdminLeagueBundle {
  const AdminLeagueBundle({
    required this.id,
    required this.name,
    required this.leagueSlugs,
    this.description,
    this.active = true,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final String? description;
  final List<String> leagueSlugs;
  final bool active;
  final int sortOrder;

  factory AdminLeagueBundle.fromJson(Map<String, dynamic> j) =>
      AdminLeagueBundle(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        leagueSlugs: (j['leagueSlugs'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(),
        active: j['active'] as bool? ?? true,
        sortOrder: (j['sortOrder'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    if (description != null) 'description': description,
    'leagueSlugs': leagueSlugs,
    'active': active,
    'sortOrder': sortOrder,
  };
}

/// Host-facing active bundle with league preview rows.
@immutable
class ActiveLeagueBundle {
  const ActiveLeagueBundle({
    required this.id,
    required this.name,
    required this.leagues,
    this.description,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final String? description;
  final int sortOrder;
  final List<AdminLeague> leagues;

  factory ActiveLeagueBundle.fromJson(Map<String, dynamic> j) =>
      ActiveLeagueBundle(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        sortOrder: (j['sortOrder'] as num?)?.toInt() ?? 0,
        leagues: (j['leagues'] as List<dynamic>? ?? const [])
            .map(
              (e) => AdminLeague.fromJson({
                ...e as Map<String, dynamic>,
                'active': true,
              }),
            )
            .toList(),
      );
}

// ── AdminAbility ───────────────────────────────────────────────────────────────

@immutable
class AdminAbility {
  const AdminAbility({
    required this.type,
    required this.name,
    required this.enabled,
    required this.color,
    required this.description,
  });

  /// 'captain' | 'yellow' | 'red' | 'extra_bench' | 'sub' | 'coach'.
  final String type;
  final String name;
  final bool enabled;

  /// Hex colour string, e.g. "#FFC83D" — same shape as AdminCardTier.color.
  final String color;

  /// Short player-facing description. Not yet rendered by any gameplay
  /// screen — this phase only adds admin editing for it. May contain
  /// chemistry placeholders (e.g. `{yellowPenalty}`).
  final String description;

  factory AdminAbility.fromJson(Map<String, dynamic> j) => AdminAbility(
    type: j['type'] as String,
    name: j['name'] as String? ?? '',
    enabled: j['enabled'] as bool? ?? true,
    color: j['color'] as String? ?? '#FFFFFF',
    description: j['description'] as String? ?? '',
  );
}

// ── AdminCardTier ──────────────────────────────────────────────────────────────

@immutable
class AdminCardTier {
  const AdminCardTier({
    required this.slug,
    required this.name,
    required this.minRating,
    required this.color,
  });

  final String slug;
  final String name;
  final int minRating;

  /// Hex string, e.g. "#FFD700".
  final String color;

  factory AdminCardTier.fromJson(Map<String, dynamic> j) => AdminCardTier(
    slug: j['slug'] as String,
    name: j['name'] as String,
    minRating: (j['minRating'] as num).toInt(),
    color: j['color'] as String? ?? '#B0BDD8',
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'minRating': minRating,
    'color': color,
  };
}

// ── AdminScoringConfig ────────────────────────────────────────────────────────
// Read-only Dart mirrors of the server's ScoringConfigValues/Version/File
// (scoring-config.ts) — used to seed the Scoring tab's form controllers and
// render the draft/published/history state. No toJson(): the tab builds the
// PUT/POST body directly from its own controllers (same pattern
// card_tiers_tab.dart's _save() uses — a raw Map, not a round-tripped model).

@immutable
class AdminScoringTierRewards {
  const AdminScoringTierRewards({
    required this.easy,
    required this.medium,
    required this.hard,
  });

  final int easy;
  final int medium;
  final int hard;

  factory AdminScoringTierRewards.fromJson(Map<String, dynamic> j) =>
      AdminScoringTierRewards(
        easy: (j['easy'] as num?)?.toInt() ?? 0,
        medium: (j['medium'] as num?)?.toInt() ?? 0,
        hard: (j['hard'] as num?)?.toInt() ?? 0,
      );
}

@immutable
class AdminScoringThresholds {
  const AdminScoringThresholds({
    required this.sameClubCount,
    required this.sameNationCount,
    required this.sameLeagueCount,
    required this.positionGroupCount,
    required this.clubAndPositionClubCount,
    required this.clubAndPositionGroupCount,
    required this.nationAndPositionNationCount,
    required this.nationAndPositionGroupCount,
  });

  final int sameClubCount;
  final int sameNationCount;
  final int sameLeagueCount;
  final int positionGroupCount;
  final int clubAndPositionClubCount;
  final int clubAndPositionGroupCount;
  final int nationAndPositionNationCount;
  final int nationAndPositionGroupCount;

  factory AdminScoringThresholds.fromJson(Map<String, dynamic> j) =>
      AdminScoringThresholds(
        sameClubCount: (j['sameClubCount'] as num?)?.toInt() ?? 0,
        sameNationCount: (j['sameNationCount'] as num?)?.toInt() ?? 0,
        sameLeagueCount: (j['sameLeagueCount'] as num?)?.toInt() ?? 0,
        positionGroupCount: (j['positionGroupCount'] as num?)?.toInt() ?? 0,
        clubAndPositionClubCount:
            (j['clubAndPositionClubCount'] as num?)?.toInt() ?? 0,
        clubAndPositionGroupCount:
            (j['clubAndPositionGroupCount'] as num?)?.toInt() ?? 0,
        nationAndPositionNationCount:
            (j['nationAndPositionNationCount'] as num?)?.toInt() ?? 0,
        nationAndPositionGroupCount:
            (j['nationAndPositionGroupCount'] as num?)?.toInt() ?? 0,
      );
}

@immutable
class AdminScoringConfigValues {
  const AdminScoringConfigValues({
    required this.rewardPerChallenge,
    required this.tierRewards,
    required this.thresholds,
    required this.bonusPerLine,
    required this.yellowPenalty,
    required this.captainMultiplier,
  });

  final int rewardPerChallenge;
  final AdminScoringTierRewards tierRewards;
  final AdminScoringThresholds thresholds;
  final int bonusPerLine;
  final int yellowPenalty;
  final int captainMultiplier;

  factory AdminScoringConfigValues.fromJson(Map<String, dynamic> j) {
    final cardChemistry = j['cardChemistry'] as Map<String, dynamic>? ?? {};
    final abilityEffects = j['abilityEffects'] as Map<String, dynamic>? ?? {};
    return AdminScoringConfigValues(
      rewardPerChallenge:
          ((j['userChallenges'] as Map<String, dynamic>?)?['rewardPerChallenge']
                  as num?)
              ?.toInt() ??
          0,
      tierRewards: AdminScoringTierRewards.fromJson(
        cardChemistry['tierRewards'] as Map<String, dynamic>? ?? {},
      ),
      thresholds: AdminScoringThresholds.fromJson(
        cardChemistry['thresholds'] as Map<String, dynamic>? ?? {},
      ),
      bonusPerLine:
          ((j['lineLeader'] as Map<String, dynamic>?)?['bonusPerLine'] as num?)
              ?.toInt() ??
          0,
      yellowPenalty: (abilityEffects['yellowPenalty'] as num?)?.toInt() ?? 0,
      captainMultiplier:
          (abilityEffects['captainMultiplier'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class AdminScoringConfigVersion {
  const AdminScoringConfigVersion({
    required this.version,
    required this.status,
    required this.createdAt,
    this.publishedAt,
    this.note,
    required this.values,
  });

  final int version;

  /// 'draft' | 'published'.
  final String status;
  final String createdAt;
  final String? publishedAt;
  final String? note;
  final AdminScoringConfigValues values;

  factory AdminScoringConfigVersion.fromJson(Map<String, dynamic> j) =>
      AdminScoringConfigVersion(
        version: (j['version'] as num?)?.toInt() ?? 0,
        status: j['status'] as String? ?? 'draft',
        createdAt: j['createdAt'] as String? ?? '',
        publishedAt: j['publishedAt'] as String?,
        note: j['note'] as String?,
        values: AdminScoringConfigValues.fromJson(
          j['values'] as Map<String, dynamic>? ?? {},
        ),
      );
}

@immutable
class AdminScoringConfigFile {
  const AdminScoringConfigFile({
    required this.draft,
    required this.published,
    required this.history,
  });

  final AdminScoringConfigVersion draft;
  final AdminScoringConfigVersion published;
  final List<AdminScoringConfigVersion> history;

  factory AdminScoringConfigFile.fromJson(Map<String, dynamic> j) =>
      AdminScoringConfigFile(
        draft: AdminScoringConfigVersion.fromJson(
          j['draft'] as Map<String, dynamic>? ?? {},
        ),
        published: AdminScoringConfigVersion.fromJson(
          j['published'] as Map<String, dynamic>? ?? {},
        ),
        history: (j['history'] as List<dynamic>? ?? [])
            .map(
              (e) =>
                  AdminScoringConfigVersion.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      );
}

// ── AdminTournamentAwardsConfig ─────────────────────────────────────────────
// Read-only Dart mirrors of the server's TournamentAwardsConfigValues/
// Version/File (tournament-awards-config.ts) — Track A final step. Same
// draft/published/history shape as AdminScoringConfig above, just a flat
// 5-field values object (no nested groups) since every field here is a
// tournament AWARD point value (champion/runner-up/top-scorer/etc.), not
// chemistry scoring.

@immutable
class AdminTournamentAwardsConfigValues {
  const AdminTournamentAwardsConfigValues({
    required this.championPoints,
    required this.runnerUpPoints,
    required this.topScorerBonus,
    required this.mostAssistsBonus,
    required this.highestRatingBonus,
  });

  final int championPoints;
  final int runnerUpPoints;
  final int topScorerBonus;
  final int mostAssistsBonus;
  final int highestRatingBonus;

  factory AdminTournamentAwardsConfigValues.fromJson(Map<String, dynamic> j) {
    return AdminTournamentAwardsConfigValues(
      championPoints: (j['championPoints'] as num?)?.toInt() ?? 0,
      runnerUpPoints: (j['runnerUpPoints'] as num?)?.toInt() ?? 0,
      topScorerBonus: (j['topScorerBonus'] as num?)?.toInt() ?? 0,
      mostAssistsBonus: (j['mostAssistsBonus'] as num?)?.toInt() ?? 0,
      highestRatingBonus: (j['highestRatingBonus'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class AdminTournamentAwardsConfigVersion {
  const AdminTournamentAwardsConfigVersion({
    required this.version,
    required this.status,
    required this.createdAt,
    this.publishedAt,
    this.note,
    required this.values,
  });

  final int version;

  /// 'draft' | 'published'.
  final String status;
  final String createdAt;
  final String? publishedAt;
  final String? note;
  final AdminTournamentAwardsConfigValues values;

  factory AdminTournamentAwardsConfigVersion.fromJson(Map<String, dynamic> j) =>
      AdminTournamentAwardsConfigVersion(
        version: (j['version'] as num?)?.toInt() ?? 0,
        status: j['status'] as String? ?? 'draft',
        createdAt: j['createdAt'] as String? ?? '',
        publishedAt: j['publishedAt'] as String?,
        note: j['note'] as String?,
        values: AdminTournamentAwardsConfigValues.fromJson(
          j['values'] as Map<String, dynamic>? ?? {},
        ),
      );
}

@immutable
class AdminTournamentAwardsConfigFile {
  const AdminTournamentAwardsConfigFile({
    required this.draft,
    required this.published,
    required this.history,
  });

  final AdminTournamentAwardsConfigVersion draft;
  final AdminTournamentAwardsConfigVersion published;
  final List<AdminTournamentAwardsConfigVersion> history;

  factory AdminTournamentAwardsConfigFile.fromJson(Map<String, dynamic> j) =>
      AdminTournamentAwardsConfigFile(
        draft: AdminTournamentAwardsConfigVersion.fromJson(
          j['draft'] as Map<String, dynamic>? ?? {},
        ),
        published: AdminTournamentAwardsConfigVersion.fromJson(
          j['published'] as Map<String, dynamic>? ?? {},
        ),
        history: (j['history'] as List<dynamic>? ?? [])
            .map(
              (e) => AdminTournamentAwardsConfigVersion.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      );
}

// ── AdminGuideSection ──────────────────────────────────────────────────────────
// One fixed Instructions/Game Guide page — key never changes, only
// title/body/order/visible are editable (PUT only, no create/delete —
// mirrors AdminAbility's fixed-list shape).

@immutable
class AdminGuideSection {
  const AdminGuideSection({
    required this.key,
    required this.title,
    required this.body,
    required this.order,
    required this.visible,
  });

  final String key;
  final String title;
  final String body;
  final int order;
  final bool visible;

  factory AdminGuideSection.fromJson(Map<String, dynamic> j) =>
      AdminGuideSection(
        key: j['key'] as String,
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        order: (j['order'] as num?)?.toInt() ?? 0,
        visible: j['visible'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
    'title': title,
    'body': body,
    'order': order,
    'visible': visible,
  };

  AdminGuideSection copyWith({
    String? title,
    String? body,
    int? order,
    bool? visible,
  }) => AdminGuideSection(
    key: key,
    title: title ?? this.title,
    body: body ?? this.body,
    order: order ?? this.order,
    visible: visible ?? this.visible,
  );
}

// ── AdminFaqItem ───────────────────────────────────────────────────────────────

@immutable
class AdminFaqItem {
  const AdminFaqItem({
    required this.id,
    required this.question,
    required this.answer,
    required this.order,
    required this.visible,
  });

  final String id;
  final String question;
  final String answer;
  final int order;
  final bool visible;

  factory AdminFaqItem.fromJson(Map<String, dynamic> j) => AdminFaqItem(
    id: j['id'] as String,
    question: j['question'] as String? ?? '',
    answer: j['answer'] as String? ?? '',
    order: (j['order'] as num?)?.toInt() ?? 0,
    visible: j['visible'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'question': question,
    'answer': answer,
    'order': order,
    'visible': visible,
  };
}

// ── AdminQuickTip ──────────────────────────────────────────────────────────────
// `phase`, when set, matches GameTurn.phase (game_state.dart) so the player
// app can show this tip contextually during that specific draft phase.

@immutable
class AdminQuickTip {
  const AdminQuickTip({
    required this.id,
    required this.text,
    this.phase,
    required this.order,
    required this.visible,
  });

  final String id;
  final String text;
  final String? phase;
  final int order;
  final bool visible;

  factory AdminQuickTip.fromJson(Map<String, dynamic> j) => AdminQuickTip(
    id: j['id'] as String,
    text: j['text'] as String? ?? '',
    phase: j['phase'] as String?,
    order: (j['order'] as num?)?.toInt() ?? 0,
    visible: j['visible'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'text': text,
    'phase': phase,
    'order': order,
    'visible': visible,
  };
}

// ── AdminContextHelp ───────────────────────────────────────────────────────────
// Content for one of the in-app "?" contextual help dialogs (Draft &
// Scoring, Abilities, Live Match Details, Result Page, Tournament). Fixed
// keys, PUT-only — same shape as AdminGuideSection, but holding the richer
// section/entry structure those dialogs actually use. Mirrors HelpSection/
// HelpEntry (shared/widgets/help_dialog.dart) exactly — see
// admin_context_help.dart's toHelpSections() for the conversion.

@immutable
class AdminContextHelpEntry {
  const AdminContextHelpEntry({required this.label, required this.body});
  final String label;
  final String body;

  factory AdminContextHelpEntry.fromJson(Map<String, dynamic> j) =>
      AdminContextHelpEntry(
        label: j['label'] as String? ?? '',
        body: j['body'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'label': label, 'body': body};
}

@immutable
class AdminContextHelpSection {
  const AdminContextHelpSection({required this.heading, required this.entries});
  final String heading;
  final List<AdminContextHelpEntry> entries;

  factory AdminContextHelpSection.fromJson(Map<String, dynamic> j) =>
      AdminContextHelpSection(
        heading: j['heading'] as String? ?? '',
        entries: (j['entries'] as List<dynamic>? ?? [])
            .map(
              (e) => AdminContextHelpEntry.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      );

  Map<String, dynamic> toJson() => {
    'heading': heading,
    'entries': entries.map((e) => e.toJson()).toList(),
  };
}

@immutable
class AdminContextHelp {
  const AdminContextHelp({
    required this.key,
    required this.title,
    required this.sections,
    required this.visible,
  });

  final String key;
  final String title;
  final List<AdminContextHelpSection> sections;
  final bool visible;

  factory AdminContextHelp.fromJson(Map<String, dynamic> j) => AdminContextHelp(
    key: j['key'] as String,
    title: j['title'] as String? ?? '',
    sections: (j['sections'] as List<dynamic>? ?? [])
        .map((s) => AdminContextHelpSection.fromJson(s as Map<String, dynamic>))
        .toList(),
    visible: j['visible'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'sections': sections.map((s) => s.toJson()).toList(),
    'visible': visible,
  };
}

// ── AdminFormation ─────────────────────────────────────────────────────────────

@immutable
class FormationSlot {
  const FormationSlot({
    required this.index,
    required this.label,
    required this.basePositionType,
  });

  final int index;
  final String label;
  final String basePositionType;

  factory FormationSlot.fromJson(Map<String, dynamic> j) => FormationSlot(
    index: (j['index'] as num).toInt(),
    label: j['label'] as String,
    basePositionType: j['basePositionType'] as String,
  );

  Map<String, dynamic> toJson() => {
    'index': index,
    'label': label,
    'basePositionType': basePositionType,
  };
}

@immutable
class AdminFormation {
  const AdminFormation({
    required this.slug,
    required this.name,
    required this.active,
    required this.slots,
  });

  final String slug;
  final String name;
  final bool active;
  final List<FormationSlot> slots;

  factory AdminFormation.fromJson(Map<String, dynamic> j) => AdminFormation(
    slug: j['slug'] as String,
    name: j['name'] as String,
    active: j['active'] as bool? ?? true,
    slots: (j['slots'] as List<dynamic>)
        .map((e) => FormationSlot.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'active': active,
    'slots': slots.map((s) => s.toJson()).toList(),
  };
}
