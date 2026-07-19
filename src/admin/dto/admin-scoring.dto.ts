import { Type } from 'class-transformer';
import {
  IsDefined,
  IsInt,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';

/**
 * Mirrors ScoringConfigValues with class-validator so the global
 * ValidationPipe rejects malformed drafts before they hit AdminService.
 * Publish-time semantic ranges still live in validateScoringConfigValues —
 * this layer only enforces shape/type/bounds.
 */

class UserChallengesDto {
  @IsInt()
  @Min(0)
  @Max(999)
  rewardPerChallenge: number;
}

class TierRewardsDto {
  @IsInt()
  @Min(0)
  @Max(999)
  easy: number;

  @IsInt()
  @Min(0)
  @Max(999)
  medium: number;

  @IsInt()
  @Min(0)
  @Max(999)
  hard: number;
}

class CardChemThresholdsDto {
  @IsInt()
  @Min(1)
  @Max(11)
  sameClubCount: number;

  @IsInt()
  @Min(1)
  @Max(11)
  sameNationCount: number;

  @IsInt()
  @Min(1)
  @Max(11)
  sameLeagueCount: number;

  @IsInt()
  @Min(1)
  @Max(11)
  positionGroupCount: number;

  @IsInt()
  @Min(1)
  @Max(11)
  clubAndPositionClubCount: number;

  @IsInt()
  @Min(1)
  @Max(11)
  clubAndPositionGroupCount: number;

  @IsInt()
  @Min(1)
  @Max(11)
  nationAndPositionNationCount: number;

  @IsInt()
  @Min(1)
  @Max(11)
  nationAndPositionGroupCount: number;
}

class CardChemistryDto {
  @ValidateNested()
  @Type(() => TierRewardsDto)
  tierRewards: TierRewardsDto;

  @ValidateNested()
  @Type(() => CardChemThresholdsDto)
  thresholds: CardChemThresholdsDto;
}

class LineLeaderDto {
  @IsInt()
  @Min(0)
  @Max(999)
  bonusPerLine: number;
}

class AbilityEffectsDto {
  @IsInt()
  @Min(0)
  @Max(999)
  yellowPenalty: number;

  @IsInt()
  @Min(1)
  @Max(10)
  captainMultiplier: number;
}

/** PUT /api/admin/scoring-config/draft — body IS the values object */
export class SaveScoringConfigDraftDto {
  @IsDefined()
  @ValidateNested()
  @Type(() => UserChallengesDto)
  userChallenges: UserChallengesDto;

  @IsDefined()
  @ValidateNested()
  @Type(() => CardChemistryDto)
  cardChemistry: CardChemistryDto;

  @IsDefined()
  @ValidateNested()
  @Type(() => LineLeaderDto)
  lineLeader: LineLeaderDto;

  @IsDefined()
  @ValidateNested()
  @Type(() => AbilityEffectsDto)
  abilityEffects: AbilityEffectsDto;
}

/** POST /api/admin/scoring-config/publish */
export class PublishScoringConfigDto {
  @IsOptional()
  @IsString()
  @MaxLength(200)
  note?: string;
}
