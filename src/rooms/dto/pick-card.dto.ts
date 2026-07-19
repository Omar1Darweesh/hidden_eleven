import { IsNotEmpty, IsString, IsUUID, MaxLength } from 'class-validator';

export class PickCardDto {
  @IsUUID('4')
  turnId: string;

  // Player-catalog card IDs come from admin-data, not generated as UUIDs —
  // validated as a bounded non-empty string, not a specific ID format.
  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  cardId: string;
}
