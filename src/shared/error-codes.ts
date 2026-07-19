/**
 * Every `{ code: '...' }` value the server can send a client, in one place.
 *
 * `rooms.gateway.ts`'s own inline literals (the early "not in a room" guards,
 * rate limiting, token verification) are replaced with `ErrorCodes.X`
 * references below. `rooms.service.ts` and `game.service.ts` still return
 * these as plain `{ error: string }` results — each string already exists in
 * exactly one place in those files (no actual duplication to centralize
 * there), and the gateway forwards whatever they return verbatim
 * (`{ code: result.error }`), so this catalog documents and types every value
 * that can flow through that pass-through without requiring an invasive
 * rewrite of two large, already-well-tested service files for the same
 * single-source-of-truth property they already have individually.
 */
export const ErrorCodes = {
  // ── Gateway-level (connection / room membership) ──────────────────────────
  NOT_IN_ROOM: 'NOT_IN_ROOM',
  NOT_FOUND: 'NOT_FOUND',
  RATE_LIMITED: 'RATE_LIMITED',
  INVALID_TOKEN: 'INVALID_TOKEN',
  VALIDATION_ERROR: 'VALIDATION_ERROR',
  INTERNAL_ERROR: 'INTERNAL_ERROR',

  // ── rooms.service.ts ────────────────────────────────────────────────────
  ROOM_NOT_FOUND: 'ROOM_NOT_FOUND',
  ROOM_STARTED: 'ROOM_STARTED',
  KICKED: 'KICKED',
  ALREADY_IN_ROOM: 'ALREADY_IN_ROOM',
  ROOM_FULL: 'ROOM_FULL',
  SPECTATORS_FULL: 'SPECTATORS_FULL',
  NOT_HOST: 'NOT_HOST',
  REQUEST_NOT_FOUND: 'REQUEST_NOT_FOUND',
  PLAYER_NOT_FOUND: 'PLAYER_NOT_FOUND',
  CANNOT_KICK_SELF: 'CANNOT_KICK_SELF',
  ALREADY_HOST: 'ALREADY_HOST',
  NOT_ENOUGH_PLAYERS: 'NOT_ENOUGH_PLAYERS',
  /** Host sent both a non-empty `leagues` list and `leagueBundleId`. */
  AMBIGUOUS_LEAGUES: 'AMBIGUOUS_LEAGUES',
  /** `leagueBundleId` unknown, inactive, or has no resolvable leagues. */
  INVALID_LEAGUE_BUNDLE: 'INVALID_LEAGUE_BUNDLE',

  // ── game.service.ts: session / phase guards (recur across most handlers) ──
  SESSION_NOT_FOUND: 'SESSION_NOT_FOUND',
  GAME_NOT_DRAFTING: 'GAME_NOT_DRAFTING',
  WRONG_PHASE: 'WRONG_PHASE',
  STALE_TURN: 'STALE_TURN',
  NOT_YOUR_TURN: 'NOT_YOUR_TURN',
  NOT_ABILITY_DRAFT: 'NOT_ABILITY_DRAFT',
  NOT_ACTIVATION_PHASE: 'NOT_ACTIVATION_PHASE',
  NOT_SUBS_PHASE: 'NOT_SUBS_PHASE',
  NO_SUBS_PHASE: 'NO_SUBS_PHASE',
  NOT_THE_PICKER: 'NOT_THE_PICKER',

  // ── game.service.ts: drafting ───────────────────────────────────────────
  INVALID_CARD: 'INVALID_CARD',
  SLOT_OUT_OF_RANGE: 'SLOT_OUT_OF_RANGE',
  SLOT_ALREADY_TAKEN: 'SLOT_ALREADY_TAKEN',
  ROUND_SLOT_ALREADY_CHOSEN: 'ROUND_SLOT_ALREADY_CHOSEN',
  INVALID_ORDER_LENGTH: 'INVALID_ORDER_LENGTH',
  INVALID_ORDER_IDS: 'INVALID_ORDER_IDS',

  // ── game.service.ts: lineup slots ───────────────────────────────────────
  PITCH_NOT_FOUND: 'PITCH_NOT_FOUND',
  SLOT_NOT_FOUND: 'SLOT_NOT_FOUND',
  SLOT_ALREADY_FILLED: 'SLOT_ALREADY_FILLED',
  SLOT_EMPTY: 'SLOT_EMPTY',
  SAME_SLOT: 'SAME_SLOT',
  SAME_ENDPOINT: 'SAME_ENDPOINT',
  CARD_NOT_FOUND: 'CARD_NOT_FOUND',

  // ── game.service.ts: abilities ──────────────────────────────────────────
  NO_ACTIVE_SLOT: 'NO_ACTIVE_SLOT',
  NO_PENDING_ABILITY: 'NO_PENDING_ABILITY',
  INVALID_TARGET: 'INVALID_TARGET',
  POSITION_MISMATCH: 'POSITION_MISMATCH',

  // ── game.service.ts: subs phase ─────────────────────────────────────────
  SUBS_ALREADY_COMPLETE: 'SUBS_ALREADY_COMPLETE',
  NO_EXTRA_BENCH: 'NO_EXTRA_BENCH',
  NO_ELIGIBLE_CLUB: 'NO_ELIGIBLE_CLUB',
  SPIN_NOT_DONE: 'SPIN_NOT_DONE',
  PLAYER_NOT_IN_POOL: 'PLAYER_NOT_IN_POOL',
  PLAYER_NOT_FROM_SPUN_CLUB: 'PLAYER_NOT_FROM_SPUN_CLUB',
  WRONG_POSITION_GROUP: 'WRONG_POSITION_GROUP',
  PLAYER_ALREADY_USED: 'PLAYER_ALREADY_USED',
  SUB_NOT_PICKED: 'SUB_NOT_PICKED',
  STARTER_NOT_FOUND: 'STARTER_NOT_FOUND',
  SUBS_NOT_COMPLETE: 'SUBS_NOT_COMPLETE',
  PLAYERS_OUT_OF_POSITION: 'PLAYERS_OUT_OF_POSITION',
  LINEUP_ALREADY_CONFIRMED: 'LINEUP_ALREADY_CONFIRMED',
  ALREADY_CONFIRMED: 'ALREADY_CONFIRMED',

  // ── game.service.ts: tournament mode ────────────────────────────────────
  TOURNAMENT_NOT_IN_READY_CHECK: 'TOURNAMENT_NOT_IN_READY_CHECK',
  TOURNAMENT_NOT_YOUR_ROUND: 'TOURNAMENT_NOT_YOUR_ROUND',
} as const;

export type ErrorCode = (typeof ErrorCodes)[keyof typeof ErrorCodes];
