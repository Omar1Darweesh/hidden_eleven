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

/**
 * Regression for the photoUrl-wiping bug: the update DTOs declare every field
 * `@IsOptional()`, and under the ES2023 tsconfig target every declared class
 * field becomes an OWN property on the validated DTO instance — set to
 * `undefined` when the client didn't send it. A naive `{ ...existing, ...dto }`
 * merge then overwrote stored values (player photoUrl, club logoUrl, …) with
 * `undefined` on any partial edit that omitted them. These tests pass a dto
 * shaped exactly like that (an explicit `photoUrl: undefined` own key) and
 * assert the stored value survives.
 */
describe('AdminService — partial update preserves omitted fields', () => {
  let service: AdminService;
  let playersFile: string;
  let clubsFile: string;

  beforeEach(() => {
    clearAllCache();
    playersFile = JSON.stringify([
      {
        id: 'p1',
        name: 'A. Hakimi',
        rating: 89,
        positions: ['RB'],
        nationality: 'Morocco',
        club: 'Paris Saint-Germain',
        league: 'Ligue 1',
        photoUrl: 'https://cdn.sofifa.net/players/235/212/26_120.png',
        pace: 92,
      },
    ]);
    clubsFile = JSON.stringify([
      { slug: 'psg', name: 'Paris Saint-Germain', league: 'Ligue 1', logoUrl: '/assets/clubs/logos/psg.png' },
    ]);

    (fs.existsSync as jest.Mock).mockReturnValue(true);
    (fs.readFileSync as jest.Mock).mockImplementation((p: string) => {
      const s = String(p);
      if (s.endsWith('players.json')) return playersFile;
      if (s.endsWith('clubs.json')) return clubsFile;
      return '[]';
    });
    (fs.writeFileSync as jest.Mock).mockImplementation((p: string, data: string) => {
      const s = String(p);
      if (s.endsWith('players.json')) playersFile = data;
      if (s.endsWith('clubs.json')) clubsFile = data;
    });
    (fs.mkdirSync as jest.Mock).mockImplementation(() => undefined);

    service = new AdminService();
  });

  it('keeps the existing photoUrl when the update omits it (dto has photoUrl: undefined)', () => {
    // Mirrors what the NestJS ValidationPipe hands the service: every optional
    // field present as an own key, unset ones being `undefined`.
    const dto: any = { rating: 90, photoUrl: undefined, clubLogoUrl: undefined };

    const updated = service.updatePlayer('p1', dto);

    expect(updated.rating).toBe(90);
    expect(updated.photoUrl).toBe('https://cdn.sofifa.net/players/235/212/26_120.png');
    // And it's actually persisted, not just returned.
    const persisted = JSON.parse(playersFile)[0];
    expect(persisted.photoUrl).toBe('https://cdn.sofifa.net/players/235/212/26_120.png');
  });

  it('still updates photoUrl when a real value IS provided', () => {
    const updated = service.updatePlayer('p1', { photoUrl: '/assets/players/photos/hakimi.png' } as any);
    expect(updated.photoUrl).toBe('/assets/players/photos/hakimi.png');
  });

  it('keeps the existing club logoUrl when the update omits it', () => {
    const updated = service.updateClub('psg', { name: 'Paris SG', logoUrl: undefined } as any);
    expect(updated.name).toBe('Paris SG');
    expect(updated.logoUrl).toBe('/assets/clubs/logos/psg.png');
  });
});
