import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsIn,
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';
import type {
  BasePositionType,
  SlotLabel,
} from '../../game/interfaces/formation.interface.js';

const SLOT_LABELS: SlotLabel[] = [
  'GK',
  'LB',
  'LWB',
  'LCB',
  'CCB',
  'RCB',
  'RB',
  'RWB',
  'LCDM',
  'CDM',
  'RCDM',
  'LM',
  'LCM',
  'CM',
  'RCM',
  'RM',
  'LAM',
  'CAM',
  'RAM',
  'LW',
  'RW',
  'CF',
  'SS',
  'LST',
  'ST',
  'RST',
];

const BASE_POSITIONS: BasePositionType[] = [
  'GK',
  'LB',
  'CB',
  'RB',
  'CDM',
  'CM',
  'CAM',
  'LM',
  'RM',
  'LW',
  'RW',
  'CF',
  'ST',
];

export class FormationSlotDto {
  @IsInt()
  @Min(0)
  @Max(10)
  index: number;

  @IsIn(SLOT_LABELS)
  label: SlotLabel;

  @IsIn(BASE_POSITIONS)
  basePositionType: BasePositionType;
}

/** POST /api/admin/formations */
export class CreateFormationDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  name: string;

  @IsBoolean()
  active: boolean;

  @IsArray()
  @ArrayMinSize(11)
  @ArrayMaxSize(11)
  @ValidateNested({ each: true })
  @Type(() => FormationSlotDto)
  slots: FormationSlotDto[];
}

/** PUT /api/admin/formations/:slug */
export class UpdateFormationDto {
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  name?: string;

  @IsOptional()
  @IsBoolean()
  active?: boolean;

  @IsOptional()
  @IsArray()
  @ArrayMinSize(11)
  @ArrayMaxSize(11)
  @ValidateNested({ each: true })
  @Type(() => FormationSlotDto)
  slots?: FormationSlotDto[];
}
