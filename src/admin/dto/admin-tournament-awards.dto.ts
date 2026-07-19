import { IsInt, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';

/**
 * Mirrors TournamentAwardsConfigValues with class-validator so the global
 * ValidationPipe rejects malformed drafts before they hit AdminService.
 * Publish-time semantic ranges still live in
 * validateTournamentAwardsConfigValues — this layer only enforces
 * shape/type/bounds, same split as admin-scoring.dto.ts.
 */

/** PUT /api/admin/tournament-awards-config/draft — body IS the values object */
export class SaveTournamentAwardsConfigDraftDto {
  @IsInt()
  @Min(0)
  @Max(999)
  championPoints: number;

  @IsInt()
  @Min(0)
  @Max(999)
  runnerUpPoints: number;

  @IsInt()
  @Min(0)
  @Max(999)
  topScorerBonus: number;

  @IsInt()
  @Min(0)
  @Max(999)
  mostAssistsBonus: number;

  @IsInt()
  @Min(0)
  @Max(999)
  highestRatingBonus: number;
}

/** POST /api/admin/tournament-awards-config/publish */
export class PublishTournamentAwardsConfigDto {
  @IsOptional()
  @IsString()
  @MaxLength(200)
  note?: string;
}
