import { IsInt, Max, Min } from 'class-validator';

/** Host adds AI opponents to an already-open lobby. */
export class AddBotDto {
  @IsInt()
  @Min(1)
  @Max(9)
  count: number;
}
