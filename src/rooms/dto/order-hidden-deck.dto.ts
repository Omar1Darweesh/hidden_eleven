import { ArrayMaxSize, IsArray, IsNotEmpty, IsString, IsUUID, MaxLength } from 'class-validator';

export class OrderHiddenDeckDto {
  @IsUUID('4')
  turnId: string;

  @IsArray()
  @ArrayMaxSize(20)
  @IsString({ each: true })
  @IsNotEmpty({ each: true })
  @MaxLength(100, { each: true })
  orderedCardIds: string[];
}
