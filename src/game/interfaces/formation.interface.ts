export type SlotLabel =
  | 'GK'
  | 'LB' | 'LWB'
  | 'LCB' | 'CCB' | 'RCB'
  | 'RB' | 'RWB'
  | 'LCDM' | 'CDM' | 'RCDM'
  | 'LM' | 'LCM' | 'CM' | 'RCM' | 'RM'
  | 'LAM' | 'CAM' | 'RAM'
  | 'LW' | 'RW'
  | 'CF' | 'SS'
  | 'LST' | 'ST' | 'RST';

export type BasePositionType =
  | 'GK'
  | 'LB' | 'CB' | 'RB'
  | 'CDM' | 'CM' | 'CAM'
  | 'LM' | 'RM'
  | 'LW' | 'RW'
  | 'CF' | 'ST';

export const LABEL_TO_BASE: Record<SlotLabel, BasePositionType> = {
  GK:   'GK',
  LB:   'LB',  LWB:  'LB',
  LCB:  'CB',  CCB:  'CB',  RCB:  'CB',
  RB:   'RB',  RWB:  'RB',
  LCDM: 'CDM', CDM:  'CDM', RCDM: 'CDM',
  LM:   'LM',
  LCM:  'CM',  CM:   'CM',  RCM:  'CM',
  RM:   'RM',
  LAM:  'CAM', CAM:  'CAM', RAM:  'CAM',
  LW:   'LW',
  RW:   'RW',
  CF:   'CF',  SS:   'CF',
  LST:  'ST',  ST:   'ST',  RST:  'ST',
};

export interface FormationSlot {
  index: number;
  label: SlotLabel;
  basePositionType: BasePositionType;
}

export interface Formation {
  slug?: string; // set when loaded from admin-data; undefined for built-in
  name: string;
  slots: FormationSlot[]; // exactly 11
}
