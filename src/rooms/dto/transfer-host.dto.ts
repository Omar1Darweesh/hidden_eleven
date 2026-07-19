import { IsUUID } from 'class-validator';

export class TransferHostDto {
  @IsUUID('4')
  targetPlayerId: string;
}
