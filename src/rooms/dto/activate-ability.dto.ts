import { IsIn, IsInt, IsOptional, IsUUID, Min } from 'class-validator';
import { COACHABLE_POSITIONS } from '../../game/interfaces/ability.interface';

/** Bench groups that exist during ability_activation (no `extra` yet). */
export const ABILITY_BENCH_GROUPS = ['att', 'mid', 'def'] as const;

/**
 * All fields optional: which combination is required depends on the
 * player's specific ability type (validated by game.service.ts, not here —
 * this DTO only guards against malformed shapes/types reaching that logic).
 */
export class ActivateAbilityDto {
  @IsOptional()
  @IsInt()
  @Min(0)
  ownSlotIndex?: number;

  @IsOptional()
  @IsUUID('4')
  targetUserId?: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  targetSlotIndex?: number;

  /** coach: the new position to add. Restricted to non-GK base positions here
   *  so a malformed/GK value never reaches the game logic (which re-checks). */
  @IsOptional()
  @IsIn(COACHABLE_POSITIONS)
  coachedPosition?: string;

  /** red/sub: rival bench group (att/mid/def). Mutual exclusion with
   *  targetSlotIndex is enforced in game.service.ts. */
  @IsOptional()
  @IsIn(ABILITY_BENCH_GROUPS)
  targetBenchGroup?: string;

  /** coach: own bench group (att/mid/def). Mutual exclusion with
   *  ownSlotIndex is enforced in game.service.ts. */
  @IsOptional()
  @IsIn(ABILITY_BENCH_GROUPS)
  ownBenchGroup?: string;
}
