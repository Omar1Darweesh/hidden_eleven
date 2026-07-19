import {
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

const HEX_COLOR = /^#[0-9A-Fa-f]{6}$/;

/** POST /api/admin/clubs */
export class CreateClubDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  name: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  league: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  logoUrl?: string;
}

/** PUT /api/admin/clubs/:slug */
export class UpdateClubDto {
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  name?: string;

  @IsOptional()
  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  league?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  logoUrl?: string;
}

/** POST /api/admin/nations */
export class CreateNationDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  name: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  flagUrl?: string;
}

/** PUT /api/admin/nations/:slug */
export class UpdateNationDto {
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  name?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  flagUrl?: string;
}

/** POST /api/admin/leagues */
export class CreateLeagueDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  name: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  logoUrl?: string;

  @IsOptional()
  @IsBoolean()
  active?: boolean;
}

/** PUT /api/admin/leagues/:slug */
export class UpdateLeagueDto {
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  name?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  logoUrl?: string;

  @IsOptional()
  @IsBoolean()
  active?: boolean;
}

/** POST /api/admin/card-tiers */
export class CreateCardTierDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  name: string;

  @IsInt()
  @Min(0)
  @Max(99)
  minRating: number;

  @IsString()
  @Matches(HEX_COLOR, { message: 'color must be a hex colour like #FFD700' })
  color: string;
}

/** PUT /api/admin/card-tiers/:slug */
export class UpdateCardTierDto {
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  name?: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(99)
  minRating?: number;

  @IsOptional()
  @IsString()
  @Matches(HEX_COLOR, { message: 'color must be a hex colour like #FFD700' })
  color?: string;
}

/** POST /api/admin/league-bundles */
export class CreateLeagueBundleDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  name: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string;

  @IsArray()
  @ArrayMinSize(1)
  @IsString({ each: true })
  @MaxLength(80, { each: true })
  leagueSlugs: string[];

  @IsOptional()
  @IsBoolean()
  active?: boolean;

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(9999)
  sortOrder?: number;
}

/** PUT /api/admin/league-bundles/:id */
export class UpdateLeagueBundleDto {
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  name?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string;

  @IsOptional()
  @IsArray()
  @ArrayMinSize(1)
  @IsString({ each: true })
  @MaxLength(80, { each: true })
  leagueSlugs?: string[];

  @IsOptional()
  @IsBoolean()
  active?: boolean;

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(9999)
  sortOrder?: number;
}

/** PUT /api/admin/abilities/:type */
export class UpdateAbilityDto {
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  name?: string;

  @IsOptional()
  @IsBoolean()
  enabled?: boolean;

  @IsOptional()
  @IsString()
  @Matches(HEX_COLOR, { message: 'color must be a hex colour like #FFC83D' })
  color?: string;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  description?: string;
}
