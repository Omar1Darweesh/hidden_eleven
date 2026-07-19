import { IsInt, IsUUID, Min } from 'class-validator';

export class PickHiddenSlotDto {
  @IsUUID('4')
  turnId: string;

  // 0-based index into orderedHiddenDeck
  @IsInt()
  @Min(0)
  slotIndex: number;
}
