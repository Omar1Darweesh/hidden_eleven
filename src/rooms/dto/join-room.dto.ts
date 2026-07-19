import { IsNotEmpty, IsString, Matches, MaxLength } from 'class-validator';

export class JoinRoomDto {
  @IsString()
  @Matches(/^[A-Za-z]{6}$/, { message: 'roomCode must be exactly 6 letters' })
  roomCode: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(40)
  displayName: string;
}
