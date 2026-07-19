import { IsInt, IsUUID, Min } from 'class-validator';

export class PickSlotDto {
  @IsUUID('4')
  turnId: string;

  @IsInt()
  @Min(0)
  slotIndex: number;
}
