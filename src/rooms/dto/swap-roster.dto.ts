import { Type } from 'class-transformer';
import { IsIn, IsInt, Min, ValidateIf, ValidateNested } from 'class-validator';

const POSITION_GROUPS = ['att', 'mid', 'def', 'extra'] as const;

/**
 * Mirrors the RosterEndpoint discriminated union
 * (`{ kind: 'pitch'; index } | { kind: 'bench'; group }`) — class-validator
 * has no native discriminated-union support, so `index`/`group` are
 * conditionally required based on `kind` via @ValidateIf. The server-side
 * service layer remains the source of truth for game-logic correctness
 * (e.g. whether that index/group is actually swappable right now); this only
 * guards against malformed shapes/types.
 */
export class RosterEndpointDto {
  @IsIn(['pitch', 'bench'])
  kind: 'pitch' | 'bench';

  @ValidateIf((o: RosterEndpointDto) => o.kind === 'pitch')
  @IsInt()
  @Min(0)
  index?: number;

  @ValidateIf((o: RosterEndpointDto) => o.kind === 'bench')
  @IsIn(POSITION_GROUPS)
  group?: 'att' | 'mid' | 'def' | 'extra';
}

export class SwapRosterDto {
  @ValidateNested()
  @Type(() => RosterEndpointDto)
  a: RosterEndpointDto;

  @ValidateNested()
  @Type(() => RosterEndpointDto)
  b: RosterEndpointDto;
}
