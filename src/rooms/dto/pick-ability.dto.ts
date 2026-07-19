import { IsInt, Min } from 'class-validator';

export class PickAbilityDto {
  @IsInt()
  @Min(0)
  cardId: number;
}
