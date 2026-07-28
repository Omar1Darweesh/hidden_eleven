import { IsInt, IsOptional, Max, Min } from 'class-validator';

/**
 * Host adjusts the draft rating window live in the lobby. Null/absent on
 * either end = no bound there (full 1–99 range). An inverted range (min >
 * max) is rejected by the gateway/service, not here.
 */
export class SetRatingRangeDto {
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(99)
  minRating?: number | null;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(99)
  maxRating?: number | null;
}
