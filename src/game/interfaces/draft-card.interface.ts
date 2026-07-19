import { BasePositionType } from './formation.interface';
import { ChemistryBonus } from '../data/league-bonus-pools.js';

export interface DraftCard {
  cardId: string;
  playerName: string;
  basePositionType: BasePositionType;
  rating: number;
  pace: number;
  shooting: number;
  passing: number;
  dribbling: number;
  defending: number;
  physical: number;
  nationality: string;
  club: string;
  /** Secondary positions the player can also play (positions[1..] from the pool). */
  altPositions: BasePositionType[];
  /** The player's FULL natural position set (primary + all alts), independent of
   *  which slot the card currently occupies. Used to validate placements when
   *  freely rearranging the lineup. */
  naturalPositions: BasePositionType[];
  /** Player photo URL. Null until real assets are available. */
  imageUrl?: string;
  /** Club badge/logo URL. Populated when real assets are available. */
  clubLogoUrl?: string;
  /** League the club belongs to — used for chemistry bonus. */
  league?: string;
  /** 3 chemistry bonus slots assigned at session creation, deterministic per player+room. */
  chemistryBonuses: ChemistryBonus[];
}
