/** How fast a tournament match's live events are delivered to clients. Purely
 *  a presentation pace — never changes the simulated result itself. */
export type SimulationSpeed = 'fast' | 'normal' | 'slow';

export interface Player {
  id: string;
  displayName: string;
  isHost: boolean;
  isConnected: boolean;
  socketId: string | null;
}

/**
 * A read-only room observer — deliberately NOT a `Player` variant (see
 * MULTIPLAYER_ROOMS_DESIGN.md, section B). Tracked in a completely separate
 * list and a separate socket index (`RoomsService.spectatorSocketIndex`,
 * never `socketIndex`) so every existing gameplay handler's
 * `getSocketEntry(client.id)` guard rejects a spectator's socket with
 * NOT_IN_ROOM automatically, with zero changes to any of those handlers —
 * a spectator is structurally invisible to the game engine by construction,
 * not by a role check someone has to remember to add.
 */
export interface Spectator {
  id: string;
  displayName: string;
  isConnected: boolean;
  socketId: string | null;
}

export interface PendingJoinRequest {
  requestId: string; // becomes playerId if approved
  displayName: string;
  socketId: string;
}

export interface Room {
  code: string;
  players: Player[];
  /** Read-only observers — never counted toward MAX_PLAYERS/MIN_PLAYERS, never part of baseTurnOrder/pitches. */
  spectators: Spectator[];
  isStarted: boolean;
  isLocked: boolean;
  kickedPlayerIds: string[];
  kickedDisplayNames: string[]; // lowercase, blocks rejoin by same display name
  pendingJoinRequests: PendingJoinRequest[];
  lastActivityAt: number; // epoch ms — updated on meaningful room events
  /**
   * League *display names* frozen at room creation (game filters by name).
   * Empty array = all leagues. When the host picked a bundle, this is a
   * snapshot of that bundle’s leagues at create time — later bundle edits
   * do not change this array.
   */
  leagues: string[];
  /** Optional provenance when the host created via a league bundle. */
  selectedBundleId?: string | null;
  selectedBundleName?: string | null;
  /** Seconds each player has per decision point. Null = no limit. */
  turnTimerSeconds: number | null;
  /** Seconds for the whole subs/bench phase. Null = no limit. */
  subsTimerSeconds: number | null;
  /** Seconds each player has to use/discard their drafted ability during the
   *  ability-activation phase. Null = no limit (same semantics as
   *  turnTimerSeconds/subsTimerSeconds — see game.service.ts's
   *  _enterActivationPhase). */
  abilityTimerSeconds: number | null;
  /** Formation slug chosen by the host. Null = server picks at random. */
  formationSlug: string | null;
  /** When true, a knockout tournament runs after the subs phase. Default false. */
  tournamentEnabled: boolean;
  /** Host-chosen tournament live-event pacing. Default 'normal'. */
  simulationSpeed: SimulationSpeed;
}
