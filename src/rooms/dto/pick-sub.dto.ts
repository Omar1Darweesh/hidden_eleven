import { IsIn, IsNotEmpty, IsString, MaxLength } from 'class-validator';

const POSITION_GROUPS = ['att', 'mid', 'def', 'extra'] as const;

export class PickSubDto {
  @IsIn(POSITION_GROUPS)
  positionGroup: 'att' | 'mid' | 'def' | 'extra';

  // Football-catalog card ID (the substitute being picked), not a room playerId.
  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  playerId: string;
}
