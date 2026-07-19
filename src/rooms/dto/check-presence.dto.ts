import { IsNotEmpty, IsString, IsUUID, Matches } from 'class-validator';

export class CheckPresenceDto {
  @IsUUID('4')
  playerId: string;

  @IsString()
  @Matches(/^[A-Za-z]{6}$/, { message: 'roomCode must be exactly 6 letters' })
  roomCode: string;

  @IsString()
  @IsNotEmpty()
  reconnectToken: string;
}
