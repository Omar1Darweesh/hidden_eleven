import { IsIn } from 'class-validator';

const POSITION_GROUPS = ['att', 'mid', 'def', 'extra'] as const;

export class RequestSubSpinDto {
  @IsIn(POSITION_GROUPS)
  positionGroup: 'att' | 'mid' | 'def' | 'extra';
}
