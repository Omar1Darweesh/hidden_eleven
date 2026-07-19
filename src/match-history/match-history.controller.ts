import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';
import { MatchHistoryService, MatchRecord } from './match-history.service.js';

const MAX_RECENT_LIMIT = 100;

@UseGuards(ThrottlerGuard)
@Controller('api/matches')
export class MatchHistoryController {
  constructor(private readonly matchHistoryService: MatchHistoryService) {}

  /**
   * Public, no auth — match history is not sensitive (room codes, display
   * names, and scores only). Rate-limited; `limit` capped at MAX_RECENT_LIMIT.
   */
  @Get('recent')
  getRecent(@Query('limit') limit?: string): MatchRecord[] {
    const parsed = limit !== undefined ? Number(limit) : 20;
    const safeLimit = Number.isFinite(parsed) && parsed > 0 ? Math.floor(parsed) : 20;
    return this.matchHistoryService.getRecentMatches(
      Math.min(safeLimit, MAX_RECENT_LIMIT),
    );
  }
}
