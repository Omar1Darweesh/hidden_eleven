import {
  ArrayMinSize,
  IsArray,
  IsIn,
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';
import type { BasePositionType } from '../../game/interfaces/formation.interface.js';

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

/** POST /api/admin/players */
export class CreatePlayerDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  name: string;

  @IsInt()
  @Min(1)
  @Max(99)
  rating: number;

  @IsArray()
  @ArrayMinSize(1)
  @IsIn(BASE_POSITIONS, { each: true })
  positions: BasePositionType[];

  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  nationality: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  club: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  photoUrl?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  clubLogoUrl?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  league?: string;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(99)
  pace?: number;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(99)
  shooting?: number;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(99)
  passing?: number;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(99)
  dribbling?: number;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(99)
  defending?: number;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(99)
  physical?: number;
}

/** PUT /api/admin/players/:id — all fields optional */
export class UpdatePlayerDto {
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  name?: string;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(99)
  rating?: number;

  @IsOptional()
  @IsArray()
  @ArrayMinSize(1)
  @IsIn(BASE_POSITIONS, { each: true })
  positions?: BasePositionType[];

  @IsOptional()
  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  nationality?: string;

  @IsOptional()
  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  club?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  photoUrl?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  clubLogoUrl?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  league?: string;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(99)
  pace?: number;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(99)
  shooting?: number;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(99)
  passing?: number;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(99)
  dribbling?: number;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(99)
  defending?: number;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(99)
  physical?: number;
}
