import { Module } from '@nestjs/common';
import { GameService } from './game.service';
import { BotService } from './bot.service.js';
import { MatchHistoryModule } from '../match-history/match-history.module.js';

@Module({
  imports: [MatchHistoryModule],
  providers: [GameService, BotService],
  exports: [GameService, BotService],
})
export class GameModule {}
