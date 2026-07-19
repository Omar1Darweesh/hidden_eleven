import { IsIn, IsNotEmpty, IsString, MaxLength } from 'class-validator';

const POSITION_GROUPS = ['att', 'mid', 'def', 'extra'] as const;

export class SwapSubDto {
  @IsIn(POSITION_GROUPS)
  positionGroup: 'att' | 'mid' | 'def' | 'extra';

  // Football-catalog card ID of the starter being swapped out, not a room playerId.
  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  starterId: string;
}
