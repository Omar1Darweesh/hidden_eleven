import { IsUUID } from 'class-validator';

export class RejectJoinDto {
  @IsUUID('4')
  requestId: string;
}
