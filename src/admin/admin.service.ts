import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import * as crypto from 'crypto';
import * as fs from 'fs';
import * as path from 'path';
import { v4 as uuidv4 } from 'uuid';
import { AdminPlayer, AdminClub, AdminNation, AdminLeague, AdminLeagueBundle, ActiveLeagueBundlePreview, AdminFormation, AdminCardTier, AdminAbility, AdminGuideSection, AdminFaqItem, AdminQuickTip, AdminContextHelp } from './interfaces/admin.interfaces.js';
import { PLAYER_POOL } from '../game/data/player-pool.js';
import { FORMATIONS } from '../game/data/formations.js';
import { CLUB_LEAGUE } from '../game/scoring.js';
import { invalidateCache } from '../game/admin-data-cache.js';
import { ScoringConfigFile, ScoringConfigValues, ScoringConfigVersion, DEFAULT_SCORING_CONFIG_V1, validateScoringConfigValues } from '../game/scoring-config.js';
import { TournamentAwardsConfigFile, TournamentAwardsConfigValues, TournamentAwardsConfigVersion, DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1, validateTournamentAwardsConfigValues } from '../game/tournament-awards-config.js';

const DATA_DIR = path.resolve(process.cwd(), 'admin-data');
const ASSETS_ROOT = path.resolve(process.cwd(), 'assets');

// ── Slug helper ───────────────────────────────────────────────────────────────

function slugify(name: string): string {
  return name
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');
}

// ── JSON file helpers ─────────────────────────────────────────────────────────

function readJson<T>(file: string): T[] {
  const filepath = path.join(DATA_DIR, file);
  if (!fs.existsSync(filepath)) return [];
  try {
    return JSON.parse(fs.readFileSync(filepath, 'utf8')) as T[];
  } catch {
    return [];
  }
}

function writeJson<T>(file: string, data: T[]): void {
  if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
  fs.writeFileSync(path.join(DATA_DIR, file), JSON.stringify(data, null, 2), 'utf8');
  // Task 2.2: single choke point for every admin-data write — invalidate
  // unconditionally rather than only for the specific files game.service.ts
  // happens to cache today. Invalidating a filename nothing has cached yet
  // (e.g. nations.json) is a harmless no-op (Map.delete on a missing key),
  // so this stays correct automatically if a new cached loader is added
  // later without this call site needing to know about it.
  invalidateCache(file);
}

// ── Seed helpers — run once if the file doesn't exist ─────────────────────────

function seedPlayers(): AdminPlayer[] {
  return PLAYER_POOL.map<AdminPlayer>(p => ({
    id: p.id,
    name: p.name,
    rating: p.rating,
    positions: p.positions,
    nationality: p.nationality,
    club: p.club,
    photoUrl: undefined,
    clubLogoUrl: p.clubLogoUrl,
  }));
}

function seedClubs(): AdminClub[] {
  const seen = new Map<string, AdminClub>();
  for (const p of PLAYER_POOL) {
    if (!seen.has(p.club)) {
      seen.set(p.club, {
        slug: slugify(p.club),
        name: p.club,
        league: CLUB_LEAGUE[p.club] ?? 'Unknown',
        logoUrl: p.clubLogoUrl,
      });
    }
  }
  return [...seen.values()].sort((a, b) => a.name.localeCompare(b.name));
}

function seedNations(): AdminNation[] {
  const seen = new Set<string>();
  const nations: AdminNation[] = [];
  for (const p of PLAYER_POOL) {
    if (p.nationality && !seen.has(p.nationality)) {
      seen.add(p.nationality);
      nations.push({ slug: slugify(p.nationality), name: p.nationality });
    }
  }
  return nations.sort((a, b) => a.name.localeCompare(b.name));
}

function seedLeagues(): AdminLeague[] {
  const seen = new Set<string>();
  const leagues: AdminLeague[] = [];
  for (const league of Object.values(CLUB_LEAGUE)) {
    if (!seen.has(league)) {
      seen.add(league);
      leagues.push({ slug: slugify(league), name: league });
    }
  }
  return leagues.sort((a, b) => a.name.localeCompare(b.name));
}

/**
 * Example reusable packs. Only includes league slugs that typically exist
 * after `seedLeagues()` / clubs enrichment — missing slugs are filtered out
 * at first write so a partial catalog still seeds cleanly.
 */
function seedLeagueBundles(availableSlugs: Set<string>): AdminLeagueBundle[] {
  const pick = (slugs: string[]) =>
    slugs.filter((s) => availableSlugs.has(s));

  const examples: Array<Omit<AdminLeagueBundle, 'id' | 'leagueSlugs'> & { leagueSlugs: string[] }> = [
    {
      name: 'Top 5 Leagues',
      description: 'Premier League, La Liga, Bundesliga, Serie A (Italy), Ligue 1.',
      leagueSlugs: pick([
        'premier-league',
        'la-liga',
        'bundesliga',
        'serie-a',
        'ligue-1',
      ]),
      active: true,
      sortOrder: 0,
    },
    {
      name: 'Europe Elite',
      description: 'Top European leagues plus Eredivisie, Primeira Liga, Süper Lig.',
      leagueSlugs: pick([
        'premier-league',
        'la-liga',
        'bundesliga',
        'serie-a',
        'ligue-1',
        'eredivisie',
        'primeira-liga',
        'super-lig',
      ]),
      active: true,
      sortOrder: 1,
    },
    {
      name: 'South America',
      description: 'Major South American domestic leagues (includes Brazilian Série A).',
      leagueSlugs: pick([
        'brasileirao-serie-a',
        'categoria-primera-a',
        'liga-profesional-de-futbol',
        'division-profesional',
        'primera-division',
      ]),
      active: true,
      sortOrder: 2,
    },
    {
      name: 'Arab World',
      description: 'Leagues commonly grouped for MENA / Arab region play.',
      leagueSlugs: pick(['pro-league', 'premyer-liqa']),
      active: true,
      sortOrder: 3,
    },
  ];

  return examples
    .filter((e) => e.leagueSlugs.length > 0)
    .map((e) => ({ ...e, id: uuidv4() }));
}

function seedFormations(): AdminFormation[] {
  return FORMATIONS.map((f) => ({
    slug: slugify(f.name),
    name: f.name,
    active: true,
    slots: f.slots,
  }));
}

function seedAbilities(): AdminAbility[] {
  // The 6 originals, all enabled by default. Colors match the Flutter
  // client's previous hardcoded AbilityMeta._table exactly (ability.dart)
  // so a fresh install/self-heal never changes existing visuals — only an
  // explicit admin edit does. Descriptions are the same migration: verbatim
  // from AbilityMeta._table's old taglines, except the two that named a
  // scoring number outright (captain/yellow) now reference it via a
  // ChemistryVars placeholder instead of a hardcoded digit — see
  // AdminAbility.description's doc comment.
  return [
    { type: 'captain',     name: 'Captain Card',     enabled: true, color: '#FFC83D', description: 'Your captained player’s chemistry counts ×{captainMultiplier}.' },
    { type: 'yellow',      name: 'Yellow Card',      enabled: true, color: '#F2C037', description: 'Knock {yellowPenalty} points off a rival’s score.' },
    { type: 'red',         name: 'Red Card',         enabled: true, color: '#E74C3C', description: 'Kill a rival player’s chemistry (rating stays).' },
    { type: 'extra_bench', name: 'Extra Bench Card', enabled: true, color: '#22D3EE', description: 'An extra sub that fits ANY position.' },
    { type: 'sub',         name: 'Sub Card',         enabled: true, color: '#2ECC71', description: 'Swap a player with a rival’s same-position player.' },
    { type: 'coach',       name: 'Coach Card',       enabled: true, color: '#A55CFF', description: 'Add a new position to one of your players.' },
  ];
}

// scoring-config.json holds a single object ({ draft, published, history }),
// not an array like every other admin-data file — readJson/writeJson<T> are
// array-shaped, so this gets its own tiny read/write pair following the exact
// same DATA_DIR/fs/invalidateCache conventions instead of forcing an object
// through the array-typed helpers.
function readScoringConfigFile(): ScoringConfigFile | null {
  const filepath = path.join(DATA_DIR, 'scoring-config.json');
  if (!fs.existsSync(filepath)) return null;
  try {
    return JSON.parse(fs.readFileSync(filepath, 'utf8')) as ScoringConfigFile;
  } catch {
    return null;
  }
}

function writeScoringConfigFile(data: ScoringConfigFile): void {
  if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
  fs.writeFileSync(
    path.join(DATA_DIR, 'scoring-config.json'),
    JSON.stringify(data, null, 2),
    'utf8',
  );
  invalidateCache('scoring-config.json');
}

function seedScoringConfig(): ScoringConfigFile {
  // v1 — matches today's pre-existing hardcoded scoring exactly. See
  // scoring-config.ts's DEFAULT_SCORING_CONFIG_V1 doc comment.
  const now = new Date().toISOString();
  const v1: ScoringConfigVersion = {
    version: 1,
    status: 'published',
    createdAt: now,
    publishedAt: now,
    note: 'Initial version — matches pre-existing hardcoded scoring exactly.',
    values: DEFAULT_SCORING_CONFIG_V1,
  };
  return { draft: v1, published: v1, history: [] };
}

// tournament-awards-config.json holds a single object
// ({ draft, published, history }), not an array — same exception as
// scoring-config.json, same read/write pair, same DATA_DIR/fs/invalidateCache
// conventions.
function readTournamentAwardsConfigFile(): TournamentAwardsConfigFile | null {
  const filepath = path.join(DATA_DIR, 'tournament-awards-config.json');
  if (!fs.existsSync(filepath)) return null;
  try {
    return JSON.parse(fs.readFileSync(filepath, 'utf8')) as TournamentAwardsConfigFile;
  } catch {
    return null;
  }
}

function writeTournamentAwardsConfigFile(data: TournamentAwardsConfigFile): void {
  if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
  fs.writeFileSync(
    path.join(DATA_DIR, 'tournament-awards-config.json'),
    JSON.stringify(data, null, 2),
    'utf8',
  );
  invalidateCache('tournament-awards-config.json');
}

function seedTournamentAwardsConfig(): TournamentAwardsConfigFile {
  // v1 — matches today's pre-existing hardcoded tournament award values
  // exactly. See tournament-awards-config.ts's
  // DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1 doc comment.
  const now = new Date().toISOString();
  const v1: TournamentAwardsConfigVersion = {
    version: 1,
    status: 'published',
    createdAt: now,
    publishedAt: now,
    note: 'Initial version — matches pre-existing hardcoded tournament awards exactly.',
    values: DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1,
  };
  return { draft: v1, published: v1, history: [] };
}

function seedCardTiers(): AdminCardTier[] {
  // Default rating bands (user-confirmed). All editable in the admin.
  return [
    { slug: 'black',  name: 'Black',  minRating: 0,  color: '#222831' },
    { slug: 'grey',   name: 'Grey',   minRating: 60, color: '#9AA5B1' },
    { slug: 'green',  name: 'Green',  minRating: 70, color: '#2ECC71' },
    { slug: 'blue',   name: 'Blue',   minRating: 75, color: '#3A8DDE' },
    { slug: 'yellow', name: 'Yellow', minRating: 80, color: '#F2C037' },
    { slug: 'gold',   name: 'Gold',   minRating: 85, color: '#FFD700' },
    { slug: 'purple', name: 'Purple', minRating: 90, color: '#A55CFF' },
  ];
}

// The fixed set of Instructions/Game Guide pages — same "known keys, no
// create/delete" shape as seedAbilities' 5 types. Adding a new page later
// means adding a key here; getGuideSections() self-heals existing installs
// the same way getAbilities() already does.
const GUIDE_SECTION_KEYS: { key: string; title: string; body: string }[] = [
  {
    key: 'overview',
    title: 'Game Overview',
    body: 'Hidden Eleven is a head-to-head football card drafting game. Build the best XI you can, then score points based on your squad\'s ratings and chemistry.',
  },
  {
    key: 'how_to_play',
    title: 'How to Play',
    body: 'Each round, players take turns picking a position, then a player card for that position. After every player has a full squad, you sub in bonus players before your final lineup is scored.',
  },
  {
    key: 'rounds',
    title: 'Round-by-Round',
    body: 'The draft plays out over 11 rounds — one per outfield position. Each round, the first picker chooses a slot and a card, then orders the remaining cards for the next round\'s hidden pick.',
  },
  {
    key: 'drafting',
    title: 'Drafting Help',
    body: 'On your turn, tap an empty slot on your pitch to choose which position you\'re drafting for, then pick a card from the offered candidates. Higher-rated cards aren\'t always the best pick — check chemistry bonuses too.',
  },
  {
    key: 'hidden_pick',
    title: 'Hidden Pick & Reveal',
    body: 'After the first pick, other players choose blind from a face-down deck. You won\'t know which card you get until you reveal it — so the order the first picker sets matters.',
  },
  {
    key: 'abilities',
    title: 'Abilities Help',
    body: 'Each player drafts one secret ability card at the start of the game (Captain, Yellow, Red, Extra Bench, or Sub). Abilities are used once, during the Ability Activation phase, before subs.',
  },
  {
    key: 'subs',
    title: 'Subs & Lineup Help',
    body: 'Spin for bonus bench players in each position group, then swap any card with any other before confirming your final lineup. Out-of-position starters block confirmation — fix them first.',
  },
  {
    key: 'scoring',
    title: 'Win Condition & Scoring',
    body: 'Your final score is your squad\'s total rating plus chemistry bonuses, minus any penalties (like a red card). The highest score wins.',
  },
];

function seedGuideSections(): AdminGuideSection[] {
  return GUIDE_SECTION_KEYS.map((s, i) => ({
    key: s.key,
    title: s.title,
    body: s.body,
    order: i,
    visible: true,
  }));
}

function seedFaqItems(): AdminFaqItem[] {
  return [
    {
      id: uuidv4(),
      question: 'What happens if I run out of time on my turn?',
      answer: 'The server automatically picks for you so the game keeps moving — an open slot and the first offered card, if a timer is configured for the room.',
      order: 0,
      visible: true,
    },
    {
      id: uuidv4(),
      question: 'Can I change my mind after picking a card?',
      answer: 'No — picks are final the moment you confirm them. Take your time before tapping a card.',
      order: 1,
      visible: true,
    },
    {
      id: uuidv4(),
      question: 'What if I lose connection mid-game?',
      answer: 'Just reopen the app — you\'ll automatically reconnect to your game in progress, with your squad and turn state intact.',
      order: 2,
      visible: true,
    },
  ];
}

function seedQuickTips(): AdminQuickTip[] {
  return [
    { id: uuidv4(), text: 'Tap any card to see its full stats before you commit.', phase: null, order: 0, visible: true },
    { id: uuidv4(), text: 'Pick your position first, then compare the offered candidates.', phase: 'selecting_position', order: 1, visible: true },
    { id: uuidv4(), text: 'A lower-rated card with the right chemistry can outscore a bigger name.', phase: 'selecting_card', order: 2, visible: true },
    { id: uuidv4(), text: 'You won\'t see the card until you reveal it — order wisely if you\'re first.', phase: 'hidden_pick', order: 3, visible: true },
    { id: uuidv4(), text: 'Fix out-of-position starters before confirming — they block your lineup.', phase: 'subs', order: 4, visible: true },
  ];
}

// The 5 in-app "?" contextual help dialogs, seeded with the EXACT text that
// used to be hardcoded client-side (game_screen.dart's _draftHelpSections,
// abilities_help.dart, match_details_panel.dart's _matchDetailsHelpSections,
// result_screen.dart's _resultHelpSections, tournament_hub_screen.dart's
// _tournamentHelpSections) — a lossless migration, not a rewrite. The client
// falls back to its own copy of this same text if this endpoint is ever
// unreachable, so nothing regresses either way.
function seedContextHelp(): AdminContextHelp[] {
  return [
    {
      key: 'draft_scoring',
      title: 'Draft & Scoring',
      visible: true,
      sections: [
        {
          heading: 'SQUAD RATING NUMBERS',
          entries: [
            {
              label: 'Raw Sum',
              body: 'The plain total of all 11 pitch cards\' ratings, added up with no averaging or chemistry. A squad-power stat only — it is NOT your final score.',
            },
            {
              label: 'Avg',
              body: 'The average rating across your 11 starters (Raw Sum ÷ 11).',
            },
            {
              label: 'DEF / MID / ATK',
              body: 'The average rating within each line (defence / midfield / attack). An out-of-position card scores 0 for its line.',
            },
          ],
        },
        {
          heading: 'FINAL SCORE',
          entries: [
            {
              label: 'How it\'s calculated',
              body: 'Final Score = (DEF avg + MID avg + ATK avg) + chemistry bonuses (user challenges, card chemistry, line leaders) ± ability effects (Captain bonus, Yellow-card penalty, Red-card nullification).',
            },
            {
              label: 'What chemistry affects',
              body: 'Chemistry bonuses only count for in-position, non-red-carded cards. Out-of-position cards contribute 0 to both their line average and their own chemistry.',
            },
          ],
        },
        {
          heading: 'ABILITY CARDS',
          entries: [
            {
              label: 'Chemistry-only, not a match event',
              body: 'The Red Card ability disables a targeted card\'s chemistry for scoring — it is pre-match/draft-phase logic only. It is NOT the same as a real red card shown in tournament match events.',
            },
          ],
        },
      ],
    },
    {
      key: 'abilities',
      title: 'Ability Cards',
      visible: true,
      sections: [
        {
          heading: 'HOW IT WORKS',
          entries: [
            {
              label: 'Pick a secret card',
              body: 'At kickoff each player draws one ability — kept hidden from everyone else.',
            },
            {
              label: 'Build your XI',
              body: 'Draft your 11 players as normal.',
            },
            {
              label: 'Play or discard',
              body: 'Before subs, use your card on a target (or discard it). Everyone sees what’s played.',
            },
            {
              label: 'Subs',
              body: 'Spin subs to recover from anything done to your squad.',
            },
          ],
        },
      ],
    },
    {
      key: 'match_details',
      title: 'Live Match Details',
      visible: true,
      sections: [
        {
          heading: 'EVENT TIMELINE',
          entries: [
            {
              label: 'Left side vs right side',
              body: 'Events for the team named on the left render on the left; the other team\'s events render on the right. A shared minute rail runs down the centre, so you can follow both teams at a glance.',
            },
            {
              label: 'Event types',
              body: '⚽ Goal (with assist if any) · 🟨 Yellow Card · 🟥 Red Card · 💨 Big Chance Missed — each shows the minute and player.',
            },
          ],
        },
        {
          heading: 'PENALTIES',
          entries: [
            {
              label: 'Shootout display',
              body: 'A match level after 90 minutes goes to a real shootout — individual kicks appear in the same timeline (labelled "P1", "P2", …), and the final result reads like "1–1 (4–3 pens)".',
            },
          ],
        },
        {
          heading: 'PLAYER STATE',
          entries: [
            {
              label: 'Sent-off players',
              body: 'Once a player receives a red card, they cannot score, assist, miss a chance, pick up another card, or take a penalty later in that same match — the event log always stays realistic.',
            },
          ],
        },
      ],
    },
    {
      key: 'result_page',
      title: 'Result Page',
      visible: true,
      sections: [
        {
          heading: 'THE WINNER',
          entries: [
            {
              label: 'Who won and why',
              body: 'The hero banner names whoever has the highest final total and gives the real reason — usually the tournament champion bonus, another tournament bonus, or simply the highest draft score.',
            },
            {
              label: 'Shared rank',
              body: 'If two or more users end with the exact same final total, they share that rank (e.g. both shown as joint 1st) rather than one being arbitrarily placed above the other.',
            },
          ],
        },
        {
          heading: 'FINAL STANDINGS & POINTS',
          entries: [
            {
              label: 'Final Score vs Final Points',
              body: 'Final Score is your draft/chemistry score alone (line averages + chemistry). Final Points is that score PLUS any tournament bonuses (champion, runner-up, award bonuses) — it\'s what actually decides the winner.',
            },
            {
              label: 'Per-user breakdown',
              body: 'Tap any row in Final Standings to see that user\'s full breakdown: base squad score, then each bonus they earned, adding up to their final total.',
            },
          ],
        },
        {
          heading: 'TOURNAMENT AWARDS',
          entries: [
            {
              label: 'Top Contributions',
              body: 'Goals + assists combined — a separate leaderboard from Top Scorer and Top Assists, showing all-round attacking impact.',
            },
            {
              label: 'Shared awards',
              body: 'If players tie on a stat (and on minutes played, where that applies), the award is shared — every tied winner is shown, each earning an equal, rounded-up share of the bonus points.',
            },
          ],
        },
      ],
    },
    {
      key: 'tournament',
      title: 'Tournament',
      visible: true,
      sections: [
        {
          heading: 'BRACKET & ROUNDS',
          entries: [
            {
              label: 'How it works',
              body: 'Teams are drawn into a knockout bracket. Win your match to advance; lose and you\'re out. The bracket at the top always shows the live state of every round.',
            },
            {
              label: 'Rounds do not auto-advance',
              body: 'A finished round stays visible so you can review it. The next round only begins once every manager presses Ready — never automatically.',
            },
          ],
        },
        {
          heading: 'READY CHECK',
          entries: [
            {
              label: 'What it means',
              body: 'Before a round\'s matches simulate, every real manager in that round must confirm Ready. Managers who don\'t respond in time are auto-readied so the tournament can continue.',
            },
          ],
        },
        {
          heading: 'LIVE MATCH DETAILS',
          entries: [
            {
              label: 'Expand a card',
              body: 'Tap a match card to open its live event timeline in place — no separate screen. Goals, cards, and big chances appear as they happen, split by team side.',
            },
            {
              label: 'Penalties',
              body: 'A match level after regulation goes to a real penalty shootout. The result reads like real football, e.g. "1–1 (4–3 pens)" — a sent-off player can never step up to take a penalty.',
            },
          ],
        },
        {
          heading: 'TOURNAMENT AWARDS',
          entries: [
            {
              label: 'How leaders are decided',
              body: 'Top Scorer and Top Assists rank by goals/assists. Top Contributions ranks by goals + assists combined. Best Rating ranks by real tournament match ratings, not pre-tournament squad rating.',
            },
            {
              label: 'Tie rules',
              body: 'A tie is broken by whichever player logged fewer minutes played (Best Rating has no minutes tiebreak). If still tied, the award is shared — every tied winner gets an equal, rounded-up share of the bonus points (e.g. 15 split 2 ways → 8 each).',
            },
          ],
        },
      ],
    },
  ];
}

// ── Service ───────────────────────────────────────────────────────────────────

@Injectable()
export class AdminService {
  private ensureSeeded(): void {
    if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
    if (!fs.existsSync(path.join(DATA_DIR, 'players.json')))
      writeJson('players.json', seedPlayers());
    if (!fs.existsSync(path.join(DATA_DIR, 'clubs.json')))
      writeJson('clubs.json', seedClubs());
    if (!fs.existsSync(path.join(DATA_DIR, 'nations.json')))
      writeJson('nations.json', seedNations());
    if (!fs.existsSync(path.join(DATA_DIR, 'leagues.json')))
      writeJson('leagues.json', seedLeagues());
    this.healSerieALeagueNameCollision();
    if (!fs.existsSync(path.join(DATA_DIR, 'league-bundles.json'))) {
      const slugs = new Set(this.getLeagues().map((l) => l.slug));
      writeJson('league-bundles.json', seedLeagueBundles(slugs));
    }
    if (!fs.existsSync(path.join(DATA_DIR, 'formations.json')))
      writeJson('formations.json', seedFormations());
    if (!fs.existsSync(path.join(DATA_DIR, 'card-tiers.json')))
      writeJson('card-tiers.json', seedCardTiers());
    if (!fs.existsSync(path.join(DATA_DIR, 'abilities.json')))
      writeJson('abilities.json', seedAbilities());
    if (!fs.existsSync(path.join(DATA_DIR, 'guide-sections.json')))
      writeJson('guide-sections.json', seedGuideSections());
    if (!fs.existsSync(path.join(DATA_DIR, 'faq.json')))
      writeJson('faq.json', seedFaqItems());
    if (!fs.existsSync(path.join(DATA_DIR, 'quick-tips.json')))
      writeJson('quick-tips.json', seedQuickTips());
    if (!fs.existsSync(path.join(DATA_DIR, 'context-help.json')))
      writeJson('context-help.json', seedContextHelp());
    if (!fs.existsSync(path.join(DATA_DIR, 'scoring-config.json')))
      writeScoringConfigFile(seedScoringConfig());
    if (!fs.existsSync(path.join(DATA_DIR, 'tournament-awards-config.json')))
      writeTournamentAwardsConfigFile(seedTournamentAwardsConfig());
  }

  onModuleInit(): void {
    this.ensureSeeded();
  }

  /**
   * `slugify("Serie A")` and `slugify("Série A")` both become `serie-a`, so a
   * single catalog row used to wipe Italian Serie A. Keep Italian on
   * `serie-a` / name `Serie A` (matches CLUB_LEAGUE) and Brazilian on
   * `brasileirao-serie-a` / name `Série A`.
   */
  private healSerieALeagueNameCollision(): void {
    const leagues = readJson<AdminLeague>('leagues.json');
    let changed = false;
    const bySlug = new Map(leagues.map((l) => [l.slug, l]));

    const serieA = bySlug.get('serie-a');
    if (serieA && serieA.name === 'Série A') {
      serieA.name = 'Serie A';
      changed = true;
    }
    if (!bySlug.has('serie-a')) {
      leagues.push({ slug: 'serie-a', name: 'Serie A', active: false });
      changed = true;
    }
    if (!bySlug.has('brasileirao-serie-a')) {
      const hasBrazilianName = leagues.some((l) => l.name === 'Série A');
      if (!hasBrazilianName) {
        leagues.push({
          slug: 'brasileirao-serie-a',
          name: 'Série A',
          active: false,
        });
        changed = true;
      }
    }

    if (changed) {
      writeJson('leagues.json', leagues);
    }

    // Point South America packs at Brazilian Série A if they still list serie-a.
    const bundles = readJson<AdminLeagueBundle>('league-bundles.json');
    let bundlesChanged = false;
    for (const b of bundles) {
      if (
        /south america/i.test(b.name) &&
        b.leagueSlugs.includes('serie-a') &&
        !b.leagueSlugs.includes('brasileirao-serie-a')
      ) {
        b.leagueSlugs = b.leagueSlugs.map((s) =>
          s === 'serie-a' ? 'brasileirao-serie-a' : s,
        );
        bundlesChanged = true;
      }
      if (/top 5/i.test(b.name) && b.description?.includes('Série A')) {
        b.description =
          'Premier League, La Liga, Bundesliga, Serie A (Italy), Ligue 1.';
        bundlesChanged = true;
      }
    }
    if (bundlesChanged) {
      writeJson('league-bundles.json', bundles);
    }
  }

  // ── Players ─────────────────────────────────────────────────────────────────

  getPlayers(): AdminPlayer[] {
    return readJson<AdminPlayer>('players.json');
  }

  getPlayer(id: string): AdminPlayer {
    const p = this.getPlayers().find(p => p.id === id);
    if (!p) throw new NotFoundException(`Player not found: ${id}`);
    return p;
  }

  createPlayer(dto: Omit<AdminPlayer, 'id'>): AdminPlayer {
    const players = this.getPlayers();
    const player: AdminPlayer = { ...dto, id: uuidv4() };
    writeJson('players.json', [...players, player]);
    return player;
  }

  updatePlayer(id: string, dto: Partial<Omit<AdminPlayer, 'id'>>): AdminPlayer {
    const players = this.getPlayers();
    const idx = players.findIndex(p => p.id === id);
    if (idx === -1) throw new NotFoundException(`Player not found: ${id}`);
    players[idx] = { ...players[idx], ...dto };
    writeJson('players.json', players);
    return players[idx];
  }

  deletePlayer(id: string): void {
    const players = this.getPlayers().filter(p => p.id !== id);
    writeJson('players.json', players);
  }

  // ── Clubs ────────────────────────────────────────────────────────────────────

  getClubs(): AdminClub[] {
    return readJson<AdminClub>('clubs.json');
  }

  getClub(slug: string): AdminClub {
    const c = this.getClubs().find(c => c.slug === slug);
    if (!c) throw new NotFoundException(`Club not found: ${slug}`);
    return c;
  }

  createClub(dto: Omit<AdminClub, 'slug'>): AdminClub {
    const clubs = this.getClubs();
    const club: AdminClub = { ...dto, slug: slugify(dto.name) };
    writeJson('clubs.json', [...clubs, club]);
    return club;
  }

  updateClub(slug: string, dto: Partial<Omit<AdminClub, 'slug'>>): AdminClub {
    const clubs = this.getClubs();
    const idx = clubs.findIndex(c => c.slug === slug);
    if (idx === -1) throw new NotFoundException(`Club not found: ${slug}`);
    clubs[idx] = { ...clubs[idx], ...dto };
    writeJson('clubs.json', clubs);
    return clubs[idx];
  }

  deleteClub(slug: string): void {
    const clubs = this.getClubs().filter(c => c.slug !== slug);
    writeJson('clubs.json', clubs);
  }

  // ── Nations ──────────────────────────────────────────────────────────────────

  getNations(): AdminNation[] {
    return readJson<AdminNation>('nations.json');
  }

  getNation(slug: string): AdminNation {
    const n = this.getNations().find(n => n.slug === slug);
    if (!n) throw new NotFoundException(`Nation not found: ${slug}`);
    return n;
  }

  createNation(dto: Omit<AdminNation, 'slug'>): AdminNation {
    const nations = this.getNations();
    const nation: AdminNation = { ...dto, slug: slugify(dto.name) };
    writeJson('nations.json', [...nations, nation]);
    return nation;
  }

  updateNation(slug: string, dto: Partial<Omit<AdminNation, 'slug'>>): AdminNation {
    const nations = this.getNations();
    const idx = nations.findIndex(n => n.slug === slug);
    if (idx === -1) throw new NotFoundException(`Nation not found: ${slug}`);
    nations[idx] = { ...nations[idx], ...dto };
    writeJson('nations.json', nations);
    return nations[idx];
  }

  deleteNation(slug: string): void {
    const nations = this.getNations().filter(n => n.slug !== slug);
    writeJson('nations.json', nations);
  }

  // ── Leagues ──────────────────────────────────────────────────────────────────

  getLeagues(): AdminLeague[] {
    return readJson<AdminLeague>('leagues.json');
  }

  getLeague(slug: string): AdminLeague {
    const l = this.getLeagues().find(l => l.slug === slug);
    if (!l) throw new NotFoundException(`League not found: ${slug}`);
    return l;
  }

  createLeague(dto: Omit<AdminLeague, 'slug'>): AdminLeague {
    const leagues = this.getLeagues();
    const slug = slugify(dto.name);
    // If a league with this slug already exists, update it instead of duplicating.
    const existingIdx = leagues.findIndex(l => l.slug === slug);
    if (existingIdx !== -1) {
      leagues[existingIdx] = { ...leagues[existingIdx], ...dto, slug };
      writeJson('leagues.json', leagues);
      return leagues[existingIdx];
    }
    const league: AdminLeague = { ...dto, slug };
    writeJson('leagues.json', [...leagues, league]);
    return league;
  }

  updateLeague(slug: string, dto: Partial<Omit<AdminLeague, 'slug'>>): AdminLeague {
    const leagues = this.getLeagues();
    const idx = leagues.findIndex(l => l.slug === slug);
    if (idx === -1) throw new NotFoundException(`League not found: ${slug}`);
    leagues[idx] = { ...leagues[idx], ...dto };
    writeJson('leagues.json', leagues);
    return leagues[idx];
  }

  deleteLeague(slug: string): void {
    const leagues = this.getLeagues().filter(l => l.slug !== slug);
    writeJson('leagues.json', leagues);
  }

  // ── League bundles ─────────────────────────────────────────────────────────

  /** Dedupe slugs while preserving first-seen order. */
  private normalizeLeagueSlugs(slugs: string[]): string[] {
    const seen = new Set<string>();
    const out: string[] = [];
    for (const raw of slugs) {
      const s = String(raw ?? '').trim();
      if (!s || seen.has(s)) continue;
      seen.add(s);
      out.push(s);
    }
    return out;
  }

  private assertLeagueSlugsExist(slugs: string[]): void {
    if (slugs.length === 0) {
      throw new BadRequestException('A league bundle must include at least one league.');
    }
    const known = new Set(this.getLeagues().map((l) => l.slug));
    const missing = slugs.filter((s) => !known.has(s));
    if (missing.length > 0) {
      throw new BadRequestException(
        `Unknown league slug(s): ${missing.join(', ')}`,
      );
    }
  }

  getLeagueBundles(): AdminLeagueBundle[] {
    return readJson<AdminLeagueBundle>('league-bundles.json').sort(
      (a, b) => a.sortOrder - b.sortOrder || a.name.localeCompare(b.name),
    );
  }

  getLeagueBundle(id: string): AdminLeagueBundle {
    const b = this.getLeagueBundles().find((x) => x.id === id);
    if (!b) throw new NotFoundException(`League bundle not found: ${id}`);
    return b;
  }

  /**
   * Host-facing list: active bundles only, with league preview fields for UI.
   */
  getActiveLeagueBundles(): ActiveLeagueBundlePreview[] {
    const bySlug = new Map(this.getLeagues().map((l) => [l.slug, l]));
    return this.getLeagueBundles()
      .filter((b) => b.active)
      .map((b) => ({
        id: b.id,
        name: b.name,
        description: b.description,
        sortOrder: b.sortOrder,
        leagues: b.leagueSlugs
          .map((slug) => bySlug.get(slug))
          .filter((l): l is AdminLeague => l != null)
          .map((l) => ({
            slug: l.slug,
            name: l.name,
            logoUrl: l.logoUrl,
          })),
      }))
      .filter((b) => b.leagues.length > 0);
  }

  createLeagueBundle(
    dto: {
      name: string;
      description?: string;
      leagueSlugs: string[];
      active?: boolean;
      sortOrder?: number;
    },
  ): AdminLeagueBundle {
    const leagueSlugs = this.normalizeLeagueSlugs(dto.leagueSlugs ?? []);
    this.assertLeagueSlugsExist(leagueSlugs);
    const bundles = this.getLeagueBundles();
    const bundle: AdminLeagueBundle = {
      id: uuidv4(),
      name: dto.name.trim(),
      description: dto.description?.trim() || undefined,
      leagueSlugs,
      active: dto.active ?? true,
      sortOrder: dto.sortOrder ?? bundles.length,
    };
    if (!bundle.name) {
      throw new BadRequestException('Bundle name is required.');
    }
    writeJson('league-bundles.json', [...bundles, bundle]);
    return bundle;
  }

  updateLeagueBundle(
    id: string,
    dto: Partial<Omit<AdminLeagueBundle, 'id'>>,
  ): AdminLeagueBundle {
    const bundles = this.getLeagueBundles();
    const idx = bundles.findIndex((b) => b.id === id);
    if (idx === -1) throw new NotFoundException(`League bundle not found: ${id}`);

    let leagueSlugs = bundles[idx].leagueSlugs;
    if (dto.leagueSlugs !== undefined) {
      leagueSlugs = this.normalizeLeagueSlugs(dto.leagueSlugs);
      this.assertLeagueSlugsExist(leagueSlugs);
    }

    const name =
      dto.name !== undefined ? dto.name.trim() : bundles[idx].name;
    if (!name) {
      throw new BadRequestException('Bundle name is required.');
    }

    bundles[idx] = {
      ...bundles[idx],
      ...dto,
      id,
      name,
      description:
        dto.description !== undefined
          ? dto.description.trim() || undefined
          : bundles[idx].description,
      leagueSlugs,
    };
    writeJson('league-bundles.json', bundles);
    return bundles[idx];
  }

  deleteLeagueBundle(id: string): void {
    const before = this.getLeagueBundles();
    if (!before.some((b) => b.id === id)) {
      throw new NotFoundException(`League bundle not found: ${id}`);
    }
    writeJson(
      'league-bundles.json',
      before.filter((b) => b.id !== id),
    );
  }

  /** Copy an existing bundle with a new id and “(copy)” name suffix. */
  duplicateLeagueBundle(id: string): AdminLeagueBundle {
    const src = this.getLeagueBundle(id);
    return this.createLeagueBundle({
      name: `${src.name} (copy)`,
      description: src.description,
      leagueSlugs: [...src.leagueSlugs],
      active: src.active,
      sortOrder: src.sortOrder + 1,
    });
  }

  /**
   * Resolve an active bundle to display names for room.create snapshot.
   * Throws NotFoundException / BadRequestException for invalid ids.
   */
  resolveLeagueBundleForRoom(id: string): {
    leagueNames: string[];
    bundle: AdminLeagueBundle;
  } {
    const bundle = this.getLeagueBundle(id);
    if (!bundle.active) {
      throw new BadRequestException(`League bundle is inactive: ${id}`);
    }
    const bySlug = new Map(this.getLeagues().map((l) => [l.slug, l]));
    const leagueNames: string[] = [];
    for (const slug of bundle.leagueSlugs) {
      const league = bySlug.get(slug);
      if (!league) {
        throw new BadRequestException(
          `League bundle references unknown slug: ${slug}`,
        );
      }
      leagueNames.push(league.name);
    }
    if (leagueNames.length === 0) {
      throw new BadRequestException('League bundle has no leagues.');
    }
    return { leagueNames, bundle };
  }

  // ── Formations ─────────────────────────────────────────────────────────────────

  getFormations(): AdminFormation[] {
    return readJson<AdminFormation>('formations.json');
  }

  getFormation(slug: string): AdminFormation {
    const f = this.getFormations().find(f => f.slug === slug);
    if (!f) throw new NotFoundException(`Formation not found: ${slug}`);
    return f;
  }

  createFormation(dto: Omit<AdminFormation, 'slug'>): AdminFormation {
    const formations = this.getFormations();
    const formation: AdminFormation = {
      ...dto,
      active: dto.active ?? true,
      slug: slugify(dto.name),
    };
    writeJson('formations.json', [...formations, formation]);
    return formation;
  }

  updateFormation(slug: string, dto: Partial<Omit<AdminFormation, 'slug'>>): AdminFormation {
    const formations = this.getFormations();
    const idx = formations.findIndex(f => f.slug === slug);
    if (idx === -1) throw new NotFoundException(`Formation not found: ${slug}`);
    formations[idx] = { ...formations[idx], ...dto };
    writeJson('formations.json', formations);
    return formations[idx];
  }

  deleteFormation(slug: string): void {
    const formations = this.getFormations().filter(f => f.slug !== slug);
    writeJson('formations.json', formations);
  }

  // ── Card tiers ─────────────────────────────────────────────────────────────────

  getCardTiers(): AdminCardTier[] {
    return readJson<AdminCardTier>('card-tiers.json')
      .sort((a, b) => a.minRating - b.minRating);
  }

  createCardTier(dto: Omit<AdminCardTier, 'slug'>): AdminCardTier {
    const tiers = this.getCardTiers();
    const tier: AdminCardTier = { ...dto, slug: slugify(dto.name) || `tier-${Date.now()}` };
    writeJson('card-tiers.json', [...tiers, tier]);
    return tier;
  }

  updateCardTier(slug: string, dto: Partial<Omit<AdminCardTier, 'slug'>>): AdminCardTier {
    const tiers = this.getCardTiers();
    const idx = tiers.findIndex(t => t.slug === slug);
    if (idx === -1) throw new NotFoundException(`Card tier not found: ${slug}`);
    tiers[idx] = { ...tiers[idx], ...dto };
    writeJson('card-tiers.json', tiers);
    return tiers[idx];
  }

  deleteCardTier(slug: string): void {
    const tiers = this.getCardTiers().filter(t => t.slug !== slug);
    writeJson('card-tiers.json', tiers);
  }

  // ── Abilities ──────────────────────────────────────────────────────────────────

  getAbilities(): AdminAbility[] {
    const stored = readJson<AdminAbility>('abilities.json');
    // Self-heal: ensure every original type is present (enabled) so a stale
    // file can't permanently hide a card after new ones are added — AND
    // backfill any FIELD a stored entry is missing (seed-first spread, then
    // the stored entry's own values win) rather than only healing whole
    // missing types. Without this, a pre-existing abilities.json written
    // before `color` was added (the exact state of every already-running
    // deployment/dev server, including this one) would keep returning
    // `color: undefined` forever — getAbilities() never re-writes the file
    // itself, so there's no other point this would ever get backfilled.
    const byType = new Map(stored.map(a => [a.type, a]));
    const merged = seedAbilities().map(seed => ({ ...seed, ...(byType.get(seed.type) ?? {}) }));
    return merged;
  }

  updateAbility(type: string, dto: Partial<Omit<AdminAbility, 'type'>>): AdminAbility {
    const abilities = this.getAbilities();
    const idx = abilities.findIndex(a => a.type === type);
    if (idx === -1) throw new NotFoundException(`Ability not found: ${type}`);
    abilities[idx] = { ...abilities[idx], ...dto, type };
    writeJson('abilities.json', abilities);
    return abilities[idx];
  }

  // ── Scoring config (Phase A/B/C — see the "Chemistry Scoring —
  // Admin-Configurable" design spec) ────────────────────────────────────────────
  // Self-heals like getAbilities(): a missing/malformed file never breaks the
  // admin UI, it just falls back to seedScoringConfig()'s v1 defaults (never
  // written to disk by a read — only ensureSeeded()/publish write the file).

  getScoringConfig(): ScoringConfigFile {
    return readScoringConfigFile() ?? seedScoringConfig();
  }

  /**
   * Saves the draft's values only — never validated, never affects any live
   * or future game (only `published` is read by GameService.createSession).
   * The draft's `version` always previews what publishing it would become
   * (currently-published version + 1), recomputed on every save so it can
   * never drift if another admin published in between edits.
   */
  saveScoringConfigDraft(values: ScoringConfigValues): ScoringConfigVersion {
    const file = this.getScoringConfig();
    const draft: ScoringConfigVersion = {
      version: file.published.version + 1,
      status: 'draft',
      createdAt: new Date().toISOString(),
      values,
    };
    const next: ScoringConfigFile = { ...file, draft };
    writeScoringConfigFile(next);
    return draft;
  }

  /**
   * Validates the current draft's values, then promotes it to `published`:
   * the old `published` is archived (unmodified) into `history`, and `draft`
   * is left as a fresh copy of the newly-published values (status: 'draft',
   * previewing the NEXT version) so the next edit starts from what's live.
   * Throws BadRequestException with every violation listed (not just the
   * first) when validation fails — draft is left untouched either way.
   */
  publishScoringConfig(note?: string): ScoringConfigFile {
    const file = this.getScoringConfig();
    const errors = validateScoringConfigValues(file.draft.values);
    if (errors.length > 0) {
      throw new BadRequestException(errors);
    }

    const now = new Date().toISOString();
    const published: ScoringConfigVersion = {
      version: file.published.version + 1,
      status: 'published',
      createdAt: now,
      publishedAt: now,
      note,
      values: file.draft.values,
    };
    const nextDraft: ScoringConfigVersion = {
      version: published.version + 1,
      status: 'draft',
      createdAt: now,
      values: published.values,
    };
    const next: ScoringConfigFile = {
      draft: nextDraft,
      published,
      history: [...file.history, file.published],
    };
    writeScoringConfigFile(next);
    return next;
  }

  // ── Tournament awards config (Track A Step 1 — server config engine only,
  // no gameplay wiring yet) ──────────────────────────────────────────────────
  // Same self-heal/draft/publish/history shape as scoring config above.

  getTournamentAwardsConfig(): TournamentAwardsConfigFile {
    return readTournamentAwardsConfigFile() ?? seedTournamentAwardsConfig();
  }

  /**
   * Saves the draft's values only — never validated, never affects any live
   * or future tournament (only `published` will be read by the future
   * beginTournament() snapshot wiring). The draft's `version` always previews
   * what publishing it would become (currently-published version + 1),
   * recomputed on every save so it can never drift if another admin
   * published in between edits.
   */
  saveTournamentAwardsConfigDraft(values: TournamentAwardsConfigValues): TournamentAwardsConfigVersion {
    const file = this.getTournamentAwardsConfig();
    const draft: TournamentAwardsConfigVersion = {
      version: file.published.version + 1,
      status: 'draft',
      createdAt: new Date().toISOString(),
      values,
    };
    const next: TournamentAwardsConfigFile = { ...file, draft };
    writeTournamentAwardsConfigFile(next);
    return draft;
  }

  /**
   * Validates the current draft's values, then promotes it to `published`:
   * the old `published` is archived (unmodified) into `history`, and `draft`
   * is left as a fresh copy of the newly-published values (status: 'draft',
   * previewing the NEXT version) so the next edit starts from what's live.
   * Throws BadRequestException with every violation listed (not just the
   * first) when validation fails — draft is left untouched either way.
   */
  publishTournamentAwardsConfig(note?: string): TournamentAwardsConfigFile {
    const file = this.getTournamentAwardsConfig();
    const errors = validateTournamentAwardsConfigValues(file.draft.values);
    if (errors.length > 0) {
      throw new BadRequestException(errors);
    }

    const now = new Date().toISOString();
    const published: TournamentAwardsConfigVersion = {
      version: file.published.version + 1,
      status: 'published',
      createdAt: now,
      publishedAt: now,
      note,
      values: file.draft.values,
    };
    const nextDraft: TournamentAwardsConfigVersion = {
      version: published.version + 1,
      status: 'draft',
      createdAt: now,
      values: published.values,
    };
    const next: TournamentAwardsConfigFile = {
      draft: nextDraft,
      published,
      history: [...file.history, file.published],
    };
    writeTournamentAwardsConfigFile(next);
    return next;
  }

  // ── Guide sections (Instructions / Game Guide) ────────────────────────────────
  // Fixed set of keys — same shape as getAbilities()/updateAbility(): no
  // create/delete, just PUT to edit one page's title/body/order/visible.

  getGuideSections(): AdminGuideSection[] {
    const stored = readJson<AdminGuideSection>('guide-sections.json');
    // Self-heal: ensure every known key is present so a stale file (or a new
    // page added in a later release) can't permanently hide a section.
    const byKey = new Map(stored.map(s => [s.key, s]));
    const merged = seedGuideSections().map(seed => byKey.get(seed.key) ?? seed);
    return merged.sort((a, b) => a.order - b.order);
  }

  updateGuideSection(key: string, dto: Partial<Omit<AdminGuideSection, 'key'>>): AdminGuideSection {
    const sections = this.getGuideSections();
    const idx = sections.findIndex(s => s.key === key);
    if (idx === -1) throw new NotFoundException(`Guide section not found: ${key}`);
    sections[idx] = { ...sections[idx], ...dto, key };
    writeJson('guide-sections.json', sections);
    return sections[idx];
  }

  // ── FAQ ────────────────────────────────────────────────────────────────────────
  // A real creatable list (unlike guide sections) — same create/update/delete
  // shape as card tiers.

  getFaqItems(): AdminFaqItem[] {
    return readJson<AdminFaqItem>('faq.json').sort((a, b) => a.order - b.order);
  }

  createFaqItem(dto: Omit<AdminFaqItem, 'id'>): AdminFaqItem {
    const items = this.getFaqItems();
    const item: AdminFaqItem = {
      question: dto.question,
      answer: dto.answer,
      visible: dto.visible ?? true,
      order: dto.order ?? items.length,
      id: uuidv4(),
    };
    writeJson('faq.json', [...items, item]);
    return item;
  }

  updateFaqItem(id: string, dto: Partial<Omit<AdminFaqItem, 'id'>>): AdminFaqItem {
    const items = this.getFaqItems();
    const idx = items.findIndex(i => i.id === id);
    if (idx === -1) throw new NotFoundException(`FAQ item not found: ${id}`);
    items[idx] = { ...items[idx], ...dto, id };
    writeJson('faq.json', items);
    return items[idx];
  }

  deleteFaqItem(id: string): void {
    const items = this.getFaqItems().filter(i => i.id !== id);
    writeJson('faq.json', items);
  }

  // ── Quick tips ───────────────────────────────────────────────────────────────
  // Same creatable-list shape as FAQ, plus an optional `phase` tag so the
  // player app can show a tip contextually during a specific draft phase.

  getQuickTips(): AdminQuickTip[] {
    return readJson<AdminQuickTip>('quick-tips.json').sort((a, b) => a.order - b.order);
  }

  createQuickTip(dto: Omit<AdminQuickTip, 'id'>): AdminQuickTip {
    const tips = this.getQuickTips();
    const tip: AdminQuickTip = {
      text: dto.text,
      phase: dto.phase ?? null,
      visible: dto.visible ?? true,
      order: dto.order ?? tips.length,
      id: uuidv4(),
    };
    writeJson('quick-tips.json', [...tips, tip]);
    return tip;
  }

  updateQuickTip(id: string, dto: Partial<Omit<AdminQuickTip, 'id'>>): AdminQuickTip {
    const tips = this.getQuickTips();
    const idx = tips.findIndex(t => t.id === id);
    if (idx === -1) throw new NotFoundException(`Quick tip not found: ${id}`);
    tips[idx] = { ...tips[idx], ...dto, id };
    writeJson('quick-tips.json', tips);
    return tips[idx];
  }

  deleteQuickTip(id: string): void {
    const tips = this.getQuickTips().filter(t => t.id !== id);
    writeJson('quick-tips.json', tips);
  }

  // ── Context help (in-app "?" dialogs) ─────────────────────────────────────────
  // Fixed set of keys, same shape as getGuideSections()/getAbilities() — no
  // create/delete, self-heals if a new dialog is added in a later release.

  getContextHelp(): AdminContextHelp[] {
    const stored = readJson<AdminContextHelp>('context-help.json');
    const byKey = new Map(stored.map(c => [c.key, c]));
    return seedContextHelp().map(seed => byKey.get(seed.key) ?? seed);
  }

  updateContextHelp(key: string, dto: Partial<Omit<AdminContextHelp, 'key'>>): AdminContextHelp {
    const items = this.getContextHelp();
    const idx = items.findIndex(c => c.key === key);
    if (idx === -1) throw new NotFoundException(`Context help not found: ${key}`);
    items[idx] = { ...items[idx], ...dto, key };
    writeJson('context-help.json', items);
    return items[idx];
  }

  // ── Asset upload ─────────────────────────────────────────────────────────────

  /**
   * Deletes a previously stored asset file (best-effort; never throws).
   * Validates the path is within ASSETS_ROOT to prevent traversal attacks.
   */
  private deleteOldAssetFile(oldPath: string | undefined): void {
    if (!oldPath || !oldPath.startsWith('/assets/')) return;
    const rel = oldPath.slice('/assets/'.length);
    const abs = path.resolve(ASSETS_ROOT, rel);
    // Reject any path that escapes the assets directory
    if (!abs.startsWith(path.resolve(ASSETS_ROOT) + path.sep)) return;
    try {
      if (fs.existsSync(abs)) fs.unlinkSync(abs);
    } catch {
      // Best-effort cleanup — don't fail the upload if deletion fails
    }
  }

  /**
   * Saves an uploaded file buffer to assets/{folder}/ with a collision-safe name.
   * Returns the stored relative URL path (e.g. /assets/players/photos/haaland-a1b2c3.png).
   */
  saveUploadedFile(folder: string, baseName: string, file: Express.Multer.File): string {
    const dir = path.join(ASSETS_ROOT, folder);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

    const ext = (path.extname(file.originalname).toLowerCase() || '.png').replace(/[^a-z0-9.]/g, '');
    const slug = slugify(baseName);
    const rand = crypto.randomBytes(4).toString('hex');
    const filename = `${slug}-${rand}${ext}`;

    fs.writeFileSync(path.join(dir, filename), file.buffer);
    return `/assets/${folder}/${filename}`;
  }

  uploadPlayerPhoto(id: string, file: Express.Multer.File): AdminPlayer {
    const player = this.getPlayer(id);
    this.deleteOldAssetFile(player.photoUrl);
    const photoUrl = this.saveUploadedFile('players/photos', player.name, file);
    return this.updatePlayer(id, { photoUrl });
  }

  uploadClubLogo(slug: string, file: Express.Multer.File): AdminClub {
    const club = this.getClub(slug);
    this.deleteOldAssetFile(club.logoUrl);
    const logoUrl = this.saveUploadedFile('clubs/logos', club.name, file);
    return this.updateClub(slug, { logoUrl });
  }

  uploadNationFlag(slug: string, file: Express.Multer.File): AdminNation {
    const nation = this.getNation(slug);
    this.deleteOldAssetFile(nation.flagUrl);
    const flagUrl = this.saveUploadedFile('nations/flags', nation.name, file);
    return this.updateNation(slug, { flagUrl });
  }

  uploadLeagueLogo(slug: string, file: Express.Multer.File): AdminLeague {
    const league = this.getLeague(slug);
    this.deleteOldAssetFile(league.logoUrl);
    const logoUrl = this.saveUploadedFile('leagues/logos', league.name, file);
    return this.updateLeague(slug, { logoUrl });
  }

  // ── Assets ───────────────────────────────────────────────────────────────────

  getAssetTree(): Record<string, string[]> {
    const result: Record<string, string[]> = {};
    const folders = ['players/photos', 'clubs/logos', 'nations/flags', 'leagues/logos', 'defaults'];
    for (const folder of folders) {
      const dir = path.join(ASSETS_ROOT, folder);
      if (fs.existsSync(dir)) {
        result[folder] = fs
          .readdirSync(dir)
          .filter(f => !f.startsWith('.'))
          .sort();
      } else {
        result[folder] = [];
      }
    }
    return result;
  }
}
