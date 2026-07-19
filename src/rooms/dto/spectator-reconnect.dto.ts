import { IsNotEmpty, IsString, IsUUID, Matches } from 'class-validator';

export class SpectatorReconnectDto {
  @IsString()
  @Matches(/^[A-Za-z]{6}$/, { message: 'roomCode must be exactly 6 letters' })
  roomCode: string;

  @IsUUID('4')
  spectatorId: string;

  @IsString()
  @IsNotEmpty()
  reconnectToken: string;
}
