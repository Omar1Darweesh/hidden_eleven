import {
  BasePositionType,
  FormationSlot,
} from '../../game/interfaces/formation.interface';

export interface AdminPlayer {
  id: string;
  name: string;
  rating: number;
  /** First entry is primary position; rest are alternate. */
  positions: BasePositionType[];
  nationality: string;
  club: string;
  /** Photo URL — may be relative path like /assets/players/photos/gk_001.png */
  photoUrl?: string;
  clubLogoUrl?: string;
  league?: string;
  pace?: number;
  shooting?: number;
  passing?: number;
  dribbling?: number;
  defending?: number;
  physical?: number;
}

export interface AdminFormation {
  slug: string;
  name: string;
  /** When false the formation is excluded from the in-game random shuffle. */
  active: boolean;
  slots: FormationSlot[];
}

export interface AdminClub {
  slug: string;
  name: string;
  league: string;
  logoUrl?: string;
}

export interface AdminNation {
  slug: string;
  name: string;
  flagUrl?: string;
}

export interface AdminLeague {
  slug: string;
  name: string;
  logoUrl?: string;
  /** When false the league is hidden from room creation (can't be played). */
  active?: boolean;
}

/**
 * Reusable pack of leagues for host room creation. Stores league *slugs*
 * (stable ids); room create resolves them to display *names* and snapshots
 * those onto `Room.leagues` so later bundle edits never affect live rooms.
 */
export interface AdminLeagueBundle {
  id: string;
  name: string;
  description?: string;
  /** League slugs included in this pack (deduped, order preserved). */
  leagueSlugs: string[];
  /** When false, hidden from the host “use a bundle” picker. */
  active: boolean;
  /** Ascending display order in admin + host lists. */
  sortOrder: number;
}

/** Host-facing active bundle with enough league identity for UI preview. */
export interface ActiveLeagueBundlePreview {
  id: string;
  name: string;
  description?: string;
  sortOrder: number;
  leagues: Array<{ slug: string; name: string; logoUrl?: string }>;
}

/**
 * One of the 6 ability cards, toggled on/off from the admin. Disabled abilities
 * are excluded from the in-game ability draft.
 */
export interface AdminAbility {
  /** Stable type key: 'captain' | 'yellow' | 'red' | 'extra_bench' | 'sub' | 'coach'. */
  type: string;
  name: string;
  /** When false the ability never appears in games. */
  enabled: boolean;
  /** Hex colour string, e.g. "#FFC83D" — same shape as AdminCardTier.color.
   *  Drives every badge/icon/highlight tied to this ability across the
   *  client (ability draft, activation screen, pitch/bench badges, log,
   *  help). See ability.dart's AbilityMeta.ensureLoaded for how the client
   *  fetches and caches this. */
  color: string;
  /**
   * Short player-facing description shown wherever the ability's tagline
   * appears (ability draft reveal card, Abilities help dialog). May contain
   * `{name}` chemistry placeholders (e.g. `{yellowPenalty}`) — see
   * ChemistryVars.resolve on the client (chemistry_vars.dart). Not yet
   * consumed by any client screen — that's a later phase.
   */
  description: string;
}

/**
 * Rating → card colour band, configurable from the admin. The game colours each
 * player card by finding the highest `minRating` band the player qualifies for.
 */
export interface AdminCardTier {
  slug: string;
  name: string;
  /** Inclusive lower bound; the band applies to ratings >= minRating. */
  minRating: number;
  /** Hex colour string, e.g. "#FFD700". */
  color: string;
}

/**
 * One built-in Instructions/Game Guide page (Game Overview, How to Play,
 * etc.) — a FIXED set of keys the admin edits content for, same
 * fixed-list/PUT-only shape as AdminAbility (no create/delete — see
 * admin.service.ts's seedGuideSections/getGuideSections, which self-heals
 * the same way getAbilities() does if a new key is ever added in code).
 */
export interface AdminGuideSection {
  /** Stable key identifying which built-in page this is — never changes.
   *  See GUIDE_SECTION_KEYS in admin.service.ts for the full fixed list. */
  key: string;
  /** Display title shown in the admin panel and the player-facing help page. */
  title: string;
  /** Body text — plain text, blank line = paragraph break. Rendered verbatim
   *  by the client (no markdown parser required). */
  body: string;
  /** Display order among guide sections (ascending). */
  order: number;
  /** When false, hidden from the player-facing help/how-to-play pages. */
  visible: boolean;
}

/**
 * One FAQ question/answer pair. Unlike AdminGuideSection this is a real
 * creatable list — admins can add/remove/reorder freely (same shape as
 * AdminCardTier/AdminLeague's create-update-delete pattern).
 */
export interface AdminFaqItem {
  id: string;
  question: string;
  answer: string;
  order: number;
  visible: boolean;
}

/**
 * One short contextual tip. `phase`, when set, lets the player app show this
 * tip as in-game contextual help during that specific draft phase — reuses
 * the exact same phase string keys as GameTurn.phase (game-session.interface.ts):
 * 'selecting_position' | 'selecting_card' | 'hidden_pick' | 'hidden_pick_reveal'
 * | 'first_player_order'. A null phase means a general tip (shown only in the
 * player app's full tips list, never as a contextual in-game tooltip).
 */
export interface AdminQuickTip {
  id: string;
  text: string;
  phase: string | null;
  order: number;
  visible: boolean;
}

/** One label + explanation line inside an AdminContextHelpSection — mirrors
 *  the client's HelpEntry (shared/widgets/help_dialog.dart) exactly. */
export interface AdminContextHelpEntry {
  label: string;
  body: string;
}

/** One titled group of entries inside an AdminContextHelp — mirrors the
 *  client's HelpSection exactly. */
export interface AdminContextHelpSection {
  heading: string;
  entries: AdminContextHelpEntry[];
}

/**
 * Content for one of the "?" contextual help dialogs already live in the app
 * (Draft & Scoring on the game screen, Abilities, Live Match Details,
 * Result Page, Tournament) — a FIXED set of keys, same PUT-only/no-create-
 * delete shape as AdminGuideSection, but holding the richer
 * section/entry structure those dialogs actually use (unlike
 * AdminGuideSection's single flat body, meant for the standalone Help page).
 * See CONTEXT_HELP_KEYS in admin.service.ts for the full fixed list.
 */
export interface AdminContextHelp {
  key: string;
  title: string;
  sections: AdminContextHelpSection[];
  visible: boolean;
}
