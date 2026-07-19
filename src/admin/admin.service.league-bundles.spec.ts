jest.mock('fs', () => ({
  ...jest.requireActual('fs'),
  existsSync: jest.fn(),
  readFileSync: jest.fn(),
  writeFileSync: jest.fn(),
  mkdirSync: jest.fn(),
}));

import * as fs from 'fs';
import { BadRequestException, NotFoundException } from '@nestjs/common';
import { AdminService } from './admin.service';
import { clearAllCache } from '../game/admin-data-cache';

describe('AdminService — league bundles', () => {
  let service: AdminService;
  let leaguesFile: string;
  let bundlesFile: string | null;

  beforeEach(() => {
    clearAllCache();
    leaguesFile = JSON.stringify([
      { slug: 'premier-league', name: 'Premier League', active: true },
      { slug: 'la-liga', name: 'La Liga', active: true },
      { slug: 'bundesliga', name: 'Bundesliga', active: false },
    ]);
    bundlesFile = null;

    (fs.existsSync as jest.Mock).mockImplementation((p: string) => {
      const s = String(p);
      if (s.endsWith('leagues.json')) return true;
      if (s.endsWith('league-bundles.json')) return bundlesFile !== null;
      return true;
    });
    (fs.readFileSync as jest.Mock).mockImplementation((p: string) => {
      const s = String(p);
      if (s.endsWith('leagues.json')) return leaguesFile;
      if (s.endsWith('league-bundles.json')) return bundlesFile ?? '[]';
      return '[]';
    });
    (fs.writeFileSync as jest.Mock).mockImplementation((p: string, data: string) => {
      const s = String(p);
      if (s.endsWith('league-bundles.json')) bundlesFile = data;
      if (s.endsWith('leagues.json')) leaguesFile = data;
    });
    (fs.mkdirSync as jest.Mock).mockImplementation(() => undefined);
    service = new AdminService();
  });

  it('creates a bundle with multiple leagues', () => {
    const bundle = service.createLeagueBundle({
      name: 'Top 5 Leagues',
      description: 'Example pack',
      leagueSlugs: ['premier-league', 'la-liga'],
      active: true,
      sortOrder: 0,
    });

    expect(bundle.id).toBeTruthy();
    expect(bundle.name).toBe('Top 5 Leagues');
    expect(bundle.leagueSlugs).toEqual(['premier-league', 'la-liga']);
    expect(service.getLeagueBundles()).toHaveLength(1);
  });

  it('dedupes duplicate league slugs inside one bundle', () => {
    const bundle = service.createLeagueBundle({
      name: 'Dupes',
      leagueSlugs: ['premier-league', 'la-liga', 'premier-league'],
      active: true,
      sortOrder: 0,
    });
    expect(bundle.leagueSlugs).toEqual(['premier-league', 'la-liga']);
  });

  it('rejects unknown league slugs', () => {
    expect(() =>
      service.createLeagueBundle({
        name: 'Bad',
        leagueSlugs: ['premier-league', 'not-a-league'],
        active: true,
        sortOrder: 0,
      }),
    ).toThrow(BadRequestException);
  });

  it('rejects empty name / empty leagues after normalize', () => {
    expect(() =>
      service.createLeagueBundle({
        name: '   ',
        leagueSlugs: ['premier-league'],
        active: true,
        sortOrder: 0,
      }),
    ).toThrow(BadRequestException);

    expect(() =>
      service.createLeagueBundle({
        name: 'Empty',
        leagueSlugs: [],
        active: true,
        sortOrder: 0,
      }),
    ).toThrow(BadRequestException);
  });

  it('getActiveLeagueBundles omits inactive bundles', () => {
    const active = service.createLeagueBundle({
      name: 'Active Pack',
      leagueSlugs: ['premier-league'],
      active: true,
      sortOrder: 0,
    });
    service.createLeagueBundle({
      name: 'Inactive Pack',
      leagueSlugs: ['la-liga'],
      active: false,
      sortOrder: 1,
    });

    const listed = service.getActiveLeagueBundles();
    expect(listed.map((b) => b.id)).toEqual([active.id]);
    expect(listed[0].leagues).toEqual([
      { slug: 'premier-league', name: 'Premier League', logoUrl: undefined },
    ]);
  });

  it('resolveLeagueBundleForRoom returns display-name snapshot', () => {
    const bundle = service.createLeagueBundle({
      name: 'Top 2',
      leagueSlugs: ['premier-league', 'la-liga'],
      active: true,
      sortOrder: 0,
    });
    const resolved = service.resolveLeagueBundleForRoom(bundle.id);
    expect(resolved.leagueNames).toEqual(['Premier League', 'La Liga']);
    expect(resolved.bundle.name).toBe('Top 2');
  });

  it('editing a bundle does not mutate a previously resolved snapshot array', () => {
    const bundle = service.createLeagueBundle({
      name: 'Snap',
      leagueSlugs: ['premier-league', 'la-liga'],
      active: true,
      sortOrder: 0,
    });
    const { leagueNames: frozen } = service.resolveLeagueBundleForRoom(bundle.id);

    service.updateLeagueBundle(bundle.id, {
      leagueSlugs: ['premier-league'],
      name: 'Snap v2',
    });

    expect(frozen).toEqual(['Premier League', 'La Liga']);
    const again = service.resolveLeagueBundleForRoom(bundle.id);
    expect(again.leagueNames).toEqual(['Premier League']);
    expect(again.bundle.name).toBe('Snap v2');
  });

  it('duplicateLeagueBundle creates a new id with (copy) name', () => {
    const src = service.createLeagueBundle({
      name: 'Europe Elite',
      leagueSlugs: ['premier-league'],
      active: true,
      sortOrder: 0,
    });
    const copy = service.duplicateLeagueBundle(src.id);
    expect(copy.id).not.toBe(src.id);
    expect(copy.name).toBe('Europe Elite (copy)');
    expect(copy.leagueSlugs).toEqual(src.leagueSlugs);
  });

  it('deleteLeagueBundle removes the pack', () => {
    const b = service.createLeagueBundle({
      name: 'Gone',
      leagueSlugs: ['la-liga'],
      active: true,
      sortOrder: 0,
    });
    service.deleteLeagueBundle(b.id);
    expect(() => service.getLeagueBundle(b.id)).toThrow(NotFoundException);
  });
});
