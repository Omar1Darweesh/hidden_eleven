import { IsUUID } from 'class-validator';

export class KickPlayerDto {
  @IsUUID('4')
  targetPlayerId: string;
}
