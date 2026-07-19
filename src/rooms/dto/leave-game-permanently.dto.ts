import { IsOptional, IsUUID, Matches } from 'class-validator';

/**
 * Both fields are optional: the gateway falls back to the socket's own
 * roomsService entry when omitted (the normal case — these exist only for
 * the "open a fresh socket after a cold start" fallback path, see
 * leaveGamePermanently in room_provider.dart).
 */
export class LeaveGamePermanentlyDto {
  @IsOptional()
  @IsUUID('4')
  playerId?: string;

  @IsOptional()
  @Matches(/^[A-Za-z]{6}$/, { message: 'roomCode must be exactly 6 letters' })
  roomCode?: string;
}
