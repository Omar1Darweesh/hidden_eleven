jest.mock('fs', () => ({
  ...jest.requireActual('fs'),
  existsSync: jest.fn(),
  readFileSync: jest.fn(),
  writeFileSync: jest.fn(),
  mkdirSync: jest.fn(),
}));

import * as fs from 'fs';
import { AdminService } from './admin.service';
import { clearAllCache } from '../game/admin-data-cache';
import { DEFAULT_SCORING_CONFIG_V1 } from '../game/scoring-config';

/**
 * AdminService's draft/publish/history lifecycle for scoring-config.json —
 * the Phase C admin-editable surface over Phase A's scoring engine. `fs` is
 * fully mocked (not the real admin-data/ dir) so each test controls exactly
 * what's "on disk" without ever touching this repo's real seed files.
 */
describe('AdminService — scoring config draft/publish', () => {
  let service: AdminService;
  let storedFile: string | null;

  beforeEach(() => {
    clearAllCache();
    storedFile = null;
    (fs.existsSync as jest.Mock).mockImplementation((p: string) => {
      if (String(p).endsWith('scoring-config.json')) return storedFile !== null;
      return true;
    });
    (fs.readFileSync as jest.Mock).mockImplementation((p: string) => {
      if (String(p).endsWith('scoring-config.json')) return storedFile ?? '';
      return '[]';
    });
    (fs.writeFileSync as jest.Mock).mockImplementation((p: string, data: string) => {
      if (String(p).endsWith('scoring-config.json')) storedFile = data;
    });
    (fs.mkdirSync as jest.Mock).mockImplementation(() => undefined);
    service = new AdminService();
  });

  it('getScoringConfig self-heals to v1 defaults when the file does not exist yet', () => {
    const file = service.getScoringConfig();
    expect(file.published.version).toBe(1);
    expect(file.published.status).toBe('published');
    expect(file.published.values).toEqual(DEFAULT_SCORING_CONFIG_V1);
    expect(file.history).toEqual([]);
  });

  it('saveScoringConfigDraft persists the edited values without touching published', () => {
    const edited = {
      ...DEFAULT_SCORING_CONFIG_V1,
      lineLeader: { bonusPerLine: 10 },
    };
    const draft = service.saveScoringConfigDraft(edited);
    expect(draft.status).toBe('draft');
    expect(draft.version).toBe(2); // previews published(1) + 1
    expect(draft.values.lineLeader.bonusPerLine).toBe(10);

    const file = service.getScoringConfig();
    expect(file.draft.values.lineLeader.bonusPerLine).toBe(10);
    expect(file.published.values.lineLeader.bonusPerLine).toBe(2); // untouched
    expect(file.published.version).toBe(1); // untouched
  });

  it('publishScoringConfig promotes the draft and archives the old published into history', () => {
    service.saveScoringConfigDraft({
      ...DEFAULT_SCORING_CONFIG_V1,
      lineLeader: { bonusPerLine: 10 },
    });
    const result = service.publishScoringConfig('bump line leader bonus');

    expect(result.published.version).toBe(2);
    expect(result.published.status).toBe('published');
    expect(result.published.values.lineLeader.bonusPerLine).toBe(10);
    expect(result.published.note).toBe('bump line leader bonus');

    expect(result.history).toHaveLength(1);
    expect(result.history[0].version).toBe(1);
    expect(result.history[0].values).toEqual(DEFAULT_SCORING_CONFIG_V1);

    // Draft is left previewing the NEXT publish, seeded from what just went live.
    expect(result.draft.version).toBe(3);
    expect(result.draft.values.lineLeader.bonusPerLine).toBe(10);
  });

  it('publishScoringConfig on an invalid draft throws and leaves the file completely untouched', () => {
    service.saveScoringConfigDraft({
      ...DEFAULT_SCORING_CONFIG_V1,
      abilityEffects: {
        ...DEFAULT_SCORING_CONFIG_V1.abilityEffects,
        yellowPenalty: -5,
      },
    });

    expect(() => service.publishScoringConfig()).toThrow();

    const file = service.getScoringConfig();
    expect(file.published.version).toBe(1); // never advanced
    // The invalid draft is left exactly as the admin typed it, so they can
    // see and fix the specific value that failed rather than losing the edit.
    expect(file.draft.values.abilityEffects.yellowPenalty).toBe(-5);
  });

  it('two publishes in a row each advance the version and keep growing history', () => {
    service.saveScoringConfigDraft({
      ...DEFAULT_SCORING_CONFIG_V1,
      abilityEffects: { ...DEFAULT_SCORING_CONFIG_V1.abilityEffects, yellowPenalty: 30 },
    });
    service.publishScoringConfig();

    service.saveScoringConfigDraft({
      ...DEFAULT_SCORING_CONFIG_V1,
      abilityEffects: { ...DEFAULT_SCORING_CONFIG_V1.abilityEffects, yellowPenalty: 40 },
    });
    const result = service.publishScoringConfig();

    expect(result.published.version).toBe(3);
    expect(result.published.values.abilityEffects.yellowPenalty).toBe(40);
    expect(result.history.map((h) => h.version)).toEqual([1, 2]);
  });
});
