import { IsUUID } from 'class-validator';

export class ConfirmHiddenRevealDto {
  @IsUUID('4')
  turnId: string;
}
