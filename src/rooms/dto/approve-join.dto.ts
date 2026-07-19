import { IsUUID } from 'class-validator';

export class ApproveJoinDto {
  @IsUUID('4')
  requestId: string;
}
