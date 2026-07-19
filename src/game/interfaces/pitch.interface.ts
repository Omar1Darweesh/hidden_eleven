import { SlotLabel, BasePositionType } from './formation.interface';
import { DraftCard } from './draft-card.interface';

export interface PitchSlot {
  index: number;
  label: SlotLabel;
  basePositionType: BasePositionType;
  card: DraftCard | null;
}

export interface Pitch {
  playerId: string;
  slots: PitchSlot[];
  filledCount: number;
}
