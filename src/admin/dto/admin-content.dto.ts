import { Type } from 'class-transformer';
import {
  IsArray,
  IsBoolean,
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  ValidateIf,
  ValidateNested,
} from 'class-validator';

/** PUT /api/admin/guide-sections/:key */
export class UpdateGuideSectionDto {
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  @MaxLength(120)
  title?: string;

  @IsOptional()
  @IsString()
  @MaxLength(50000)
  body?: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(9999)
  order?: number;

  @IsOptional()
  @IsBoolean()
  visible?: boolean;
}

/** POST /api/admin/faq */
export class CreateFaqDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(500)
  question: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(10000)
  answer: string;

  @IsInt()
  @Min(0)
  @Max(9999)
  order: number;

  @IsBoolean()
  visible: boolean;
}

/** PUT /api/admin/faq/:id */
export class UpdateFaqDto {
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  @MaxLength(500)
  question?: string;

  @IsOptional()
  @IsString()
  @IsNotEmpty()
  @MaxLength(10000)
  answer?: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(9999)
  order?: number;

  @IsOptional()
  @IsBoolean()
  visible?: boolean;
}

/** POST /api/admin/quick-tips */
export class CreateQuickTipDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(500)
  text: string;

  /** null = general tip; otherwise a GameTurn.phase string. */
  @ValidateIf((_, v) => v !== null)
  @IsOptional()
  @IsString()
  @MaxLength(60)
  phase: string | null;

  @IsInt()
  @Min(0)
  @Max(9999)
  order: number;

  @IsBoolean()
  visible: boolean;
}

/** PUT /api/admin/quick-tips/:id */
export class UpdateQuickTipDto {
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  @MaxLength(500)
  text?: string;

  @ValidateIf((_, v) => v !== null && v !== undefined)
  @IsOptional()
  @IsString()
  @MaxLength(60)
  phase?: string | null;

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(9999)
  order?: number;

  @IsOptional()
  @IsBoolean()
  visible?: boolean;
}

export class ContextHelpEntryDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(120)
  label: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(5000)
  body: string;
}

export class ContextHelpSectionDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(120)
  heading: string;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => ContextHelpEntryDto)
  entries: ContextHelpEntryDto[];
}

/** PUT /api/admin/context-help/:key */
export class UpdateContextHelpDto {
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  @MaxLength(120)
  title?: string;

  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => ContextHelpSectionDto)
  sections?: ContextHelpSectionDto[];

  @IsOptional()
  @IsBoolean()
  visible?: boolean;
}
