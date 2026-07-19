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
import { DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1 } from '../game/tournament-awards-config';

/**
 * AdminService's draft/publish/history lifecycle for
 * tournament-awards-config.json — Track A Step 1's server config engine,
 * mirroring admin.service.scoring-config.spec.ts exactly. `fs` is fully
 * mocked (not the real admin-data/ dir) so each test controls exactly what's
 * "on disk" without ever touching this repo's real seed files.
 */
describe('AdminService — tournament awards config draft/publish', () => {
  let service: AdminService;
  let storedFile: string | null;

  beforeEach(() => {
    clearAllCache();
    storedFile = null;
    (fs.existsSync as jest.Mock).mockImplementation((p: string) => {
      if (String(p).endsWith('tournament-awards-config.json')) return storedFile !== null;
      return true;
    });
    (fs.readFileSync as jest.Mock).mockImplementation((p: string) => {
      if (String(p).endsWith('tournament-awards-config.json')) return storedFile ?? '';
      return '[]';
    });
    (fs.writeFileSync as jest.Mock).mockImplementation((p: string, data: string) => {
      if (String(p).endsWith('tournament-awards-config.json')) storedFile = data;
    });
    (fs.mkdirSync as jest.Mock).mockImplementation(() => undefined);
    service = new AdminService();
  });

  it('getTournamentAwardsConfig self-heals to v1 defaults when the file does not exist yet', () => {
    const file = service.getTournamentAwardsConfig();
    expect(file.published.version).toBe(1);
    expect(file.published.status).toBe('published');
    expect(file.published.values).toEqual(DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1);
    expect(file.history).toEqual([]);
  });

  it('saveTournamentAwardsConfigDraft persists the edited values without touching published', () => {
    const edited = {
      ...DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1,
      topScorerBonus: 25,
    };
    const draft = service.saveTournamentAwardsConfigDraft(edited);
    expect(draft.status).toBe('draft');
    expect(draft.version).toBe(2); // previews published(1) + 1
    expect(draft.values.topScorerBonus).toBe(25);

    const file = service.getTournamentAwardsConfig();
    expect(file.draft.values.topScorerBonus).toBe(25);
    expect(file.published.values.topScorerBonus).toBe(15); // untouched
    expect(file.published.version).toBe(1); // untouched
  });

  it('publishTournamentAwardsConfig promotes the draft and archives the old published into history', () => {
    service.saveTournamentAwardsConfigDraft({
      ...DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1,
      championPoints: 75,
    });
    const result = service.publishTournamentAwardsConfig('bump champion points');

    expect(result.published.version).toBe(2);
    expect(result.published.status).toBe('published');
    expect(result.published.values.championPoints).toBe(75);
    expect(result.published.note).toBe('bump champion points');

    expect(result.history).toHaveLength(1);
    expect(result.history[0].version).toBe(1);
    expect(result.history[0].values).toEqual(DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1);

    // Draft is left previewing the NEXT publish, seeded from what just went live.
    expect(result.draft.version).toBe(3);
    expect(result.draft.values.championPoints).toBe(75);
  });

  it('publishTournamentAwardsConfig on an invalid draft throws and leaves the file completely untouched', () => {
    service.saveTournamentAwardsConfigDraft({
      ...DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1,
      runnerUpPoints: -5,
    });

    expect(() => service.publishTournamentAwardsConfig()).toThrow();

    const file = service.getTournamentAwardsConfig();
    expect(file.published.version).toBe(1); // never advanced
    // The invalid draft is left exactly as the admin typed it, so they can
    // see and fix the specific value that failed rather than losing the edit.
    expect(file.draft.values.runnerUpPoints).toBe(-5);
  });

  it('two publishes in a row each advance the version and keep growing history', () => {
    service.saveTournamentAwardsConfigDraft({
      ...DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1,
      mostAssistsBonus: 20,
    });
    service.publishTournamentAwardsConfig();

    service.saveTournamentAwardsConfigDraft({
      ...DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1,
      mostAssistsBonus: 30,
    });
    const result = service.publishTournamentAwardsConfig();

    expect(result.published.version).toBe(3);
    expect(result.published.values.mostAssistsBonus).toBe(30);
    expect(result.history.map((h) => h.version)).toEqual([1, 2]);
  });
});
