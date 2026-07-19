import { Module } from '@nestjs/common';
import { GameService } from './game.service';
import { MatchHistoryModule } from '../match-history/match-history.module.js';

@Module({
  imports: [MatchHistoryModule],
  providers: [GameService],
  exports: [GameService],
})
export class GameModule {}
