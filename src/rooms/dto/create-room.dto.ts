import { IsArray, IsBoolean, IsIn, IsInt, IsNotEmpty, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';
import type { SimulationSpeed } from '../interfaces/room.interface';

export class CreateRoomDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(40)
  displayName: string;

  /**
   * Manual league selection: display *names* (not slugs) matching player/
   * club league strings. Empty / absent = all leagues when no bundle id.
   * Mutually exclusive with a non-empty selection + `leagueBundleId`
   * (gateway rejects ambiguous payloads).
   */
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(60, { each: true })
  leagues?: string[];

  /**
   * Optional admin league-bundle id. When set, the server resolves the
   * bundle and snapshots its league *names* onto the room — do not also
   * send a non-empty `leagues` array.
   */
  @IsOptional()
  @IsString()
  @MaxLength(80)
  leagueBundleId?: string;

  /** Seconds per decision point. Null or absent = no limit. */
  @IsOptional()
  @IsInt()
  @Min(5)
  @Max(300)
  turnTimerSeconds?: number | null;

  /** Seconds for the whole subs/bench phase. On expiry the lineup is auto-confirmed
   *  and the game ends. Null or absent = no limit. */
  @IsOptional()
  @IsInt()
  @Min(10)
  @Max(1800)
  subsTimerSeconds?: number | null;

  /** Seconds each player has to use/discard their drafted ability. Null or
   *  absent = no limit. */
  @IsOptional()
  @IsInt()
  @Min(10)
  @Max(300)
  abilityTimerSeconds?: number | null;

  /** Formation slug to use. Absent or null = server picks at random. */
  @IsOptional()
  @IsString()
  @MaxLength(60)
  formationSlug?: string | null;

  /** When true, a knockout tournament runs after the subs phase instead of going
   *  straight to the result screen. Absent = false (normal game). */
  @IsOptional()
  @IsBoolean()
  tournamentEnabled?: boolean;

  /** How fast tournament match events are delivered to clients — a pacing/
   *  presentation choice only, never a change to the simulated result.
   *  Absent = 'normal' (today's existing pacing). */
  @IsOptional()
  @IsIn(['fast', 'normal', 'slow'])
  simulationSpeed?: SimulationSpeed;
}
