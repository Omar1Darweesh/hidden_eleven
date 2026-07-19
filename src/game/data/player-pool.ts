import { BasePositionType } from '../interfaces/formation.interface';

export interface PlayerCardDefinition {
  id: string;
  name: string;
  rating: number;
  /** First entry is primary position; remaining are secondary (eligible for those slots too). */
  positions: BasePositionType[];
  nationality: string;
  club: string;
  /** Club badge URL. Populated when real assets are available; clients fall back to name-based lookup. */
  clubLogoUrl?: string;
  /** Player photo URL (relative path, e.g. /assets/players/photos/...). */
  photoUrl?: string;
  /** League the player's club belongs to (carried in admin-data/players.json). */
  league?: string;
  // Real per-attribute ratings (from the dataset). When absent the server
  // derives approximate values from `rating` in toCard().
  pace?: number;
  shooting?: number;
  passing?: number;
  dribbling?: number;
  defending?: number;
  physical?: number;
}

/** Compact factory — keeps the list below readable. */
const p = (
  id: string,
  name: string,
  rating: number,
  positions: BasePositionType[],
  nationality: string,
  club: string,
): PlayerCardDefinition => ({ id, name, rating, positions, nationality, club });

// ── Player pool (~176 players) ────────────────────────────────────────────────
// Enough to run a full 11-round draft with 4 players (44 cards drafted)
// while still offering fresh 3-card candidate sets every turn.

export const PLAYER_POOL: PlayerCardDefinition[] = [
  // ── GK (10) ──────────────────────────────────────────────────────────────
  p('gk_001', 'Alisson Becker',         91, ['GK'],        'Brazil',      'Liverpool FC'),
  p('gk_002', 'Ederson Moraes',         90, ['GK'],        'Brazil',      'Manchester City'),
  p('gk_003', 'Manuel Neuer',           89, ['GK'],        'Germany',     'Bayern Munich'),
  p('gk_004', 'Thibaut Courtois',       91, ['GK'],        'Belgium',     'Real Madrid'),
  p('gk_005', 'Jan Oblak',             90, ['GK'],        'Slovenia',    'Atlético Madrid'),
  p('gk_006', 'Gianluigi Donnarumma',  89, ['GK'],        'Italy',       'Paris Saint-Germain'),
  p('gk_007', 'Marc-André ter Stegen', 88, ['GK'],        'Germany',     'FC Barcelona'),
  p('gk_008', 'Hugo Lloris',           87, ['GK'],        'France',      'Tottenham Hotspur'),
  p('gk_009', 'Jordan Pickford',       85, ['GK'],        'England',     'Everton'),
  p('gk_010', 'David de Gea',          85, ['GK'],        'Spain',       'Manchester United'),

  // ── LB (13) ──────────────────────────────────────────────────────────────
  p('lb_001', 'Andrew Robertson',      88, ['LB'],        'Scotland',    'Liverpool FC'),
  p('lb_002', 'Alphonso Davies',        86, ['LB'],        'Canada',      'Bayern Munich'),
  p('lb_003', 'Théo Hernandez',         86, ['LB'],        'France',      'AC Milan'),
  p('lb_004', 'Jordi Alba',             85, ['LB'],        'Spain',       'Inter Miami'),
  p('lb_005', 'Ben Chilwell',           83, ['LB'],        'England',     'Chelsea'),
  p('lb_006', 'Luke Shaw',              84, ['LB'],        'England',     'Manchester United'),
  p('lb_007', 'Lucas Hernandez',        84, ['LB'],        'France',      'Bayern Munich'),
  p('lb_008', 'Alex Telles',            81, ['LB'],        'Brazil',      'Sevilla'),
  p('lb_009', 'Joakim Maehle',          80, ['LB'],        'Denmark',     'Atalanta'),
  p('lb_010', 'Robin Gosens',           80, ['LB'],        'Germany',     'Inter Milan'),
  p('lb_011', 'Alejandro Grimaldo',     82, ['LB'],        'Spain',       'Bayer Leverkusen'),
  p('lb_012', 'Kostas Tsimikas',        79, ['LB'],        'Greece',      'Liverpool FC'),
  p('lb_013', 'Renan Lodi',             81, ['LB'],        'Brazil',      'Nottingham Forest'),

  // ── CB (22) ──────────────────────────────────────────────────────────────
  p('cb_001', 'Virgil van Dijk',        91, ['CB'],        'Netherlands', 'Liverpool FC'),
  p('cb_002', 'Rúben Dias',             90, ['CB'],        'Portugal',    'Manchester City'),
  p('cb_003', 'Aymeric Laporte',        88, ['CB', 'LB'],  'Spain',       'Al-Nassr'),
  p('cb_004', 'Kalidou Koulibaly',      87, ['CB'],        'Senegal',     'Al-Hilal'),
  p('cb_005', 'Marquinhos',             89, ['CB'],        'Brazil',      'Paris Saint-Germain'),
  p('cb_006', 'Éder Militão',           88, ['CB'],        'Brazil',      'Real Madrid'),
  p('cb_007', 'David Alaba',            87, ['CB', 'LB'],  'Austria',     'Real Madrid'),
  p('cb_008', 'Giorgio Chiellini',      85, ['CB'],        'Italy',       'Retired'),
  p('cb_009', 'Leonardo Bonucci',       84, ['CB'],        'Italy',       'Union Berlin'),
  p('cb_010', 'Presnel Kimpembe',       84, ['CB'],        'France',      'Paris Saint-Germain'),
  p('cb_011', 'Matthijs de Ligt',       86, ['CB'],        'Netherlands', 'Bayern Munich'),
  p('cb_012', 'Dayot Upamecano',        84, ['CB'],        'France',      'Bayern Munich'),
  p('cb_013', 'Raphaël Varane',         85, ['CB'],        'France',      'Como 1907'),
  p('cb_014', 'John Stones',            86, ['CB'],        'England',     'Manchester City'),
  p('cb_015', 'Harry Maguire',          82, ['CB'],        'England',     'Manchester United'),
  p('cb_016', 'Fikayo Tomori',          83, ['CB'],        'England',     'AC Milan'),
  p('cb_017', 'Joško Gvardiol',         86, ['CB', 'LB'],  'Croatia',     'Manchester City'),
  p('cb_018', 'William Saliba',         87, ['CB'],        'France',      'Arsenal'),
  p('cb_019', 'Niklas Süle',            83, ['CB', 'RB'],  'Germany',     'Borussia Dortmund'),
  p('cb_020', 'Jules Koundé',           84, ['CB', 'RB'],  'France',      'FC Barcelona'),
  p('cb_021', 'Antonio Rüdiger',        84, ['CB'],        'Germany',     'Real Madrid'),
  p('cb_022', 'Stefan de Vrij',         83, ['CB'],        'Netherlands', 'Inter Milan'),

  // ── RB (13) ──────────────────────────────────────────────────────────────
  p('rb_001', 'Trent Alexander-Arnold', 88, ['RB'],        'England',     'Liverpool FC'),
  p('rb_002', 'Achraf Hakimi',          87, ['RB'],        'Morocco',     'Paris Saint-Germain'),
  p('rb_003', 'Reece James',            87, ['RB'],        'England',     'Chelsea'),
  p('rb_004', 'João Cancelo',           88, ['RB', 'LB'],  'Portugal',    'Bayern Munich'),
  p('rb_005', 'Kyle Walker',            85, ['RB'],        'England',     'Manchester City'),
  p('rb_006', 'César Azpilicueta',      83, ['RB', 'CB'],  'Spain',       'Atlético Madrid'),
  p('rb_007', 'Aaron Wan-Bissaka',      80, ['RB'],        'England',     'West Ham'),
  p('rb_008', 'Denzel Dumfries',        83, ['RB'],        'Netherlands', 'Inter Milan'),
  p('rb_009', 'Benjamin Pavard',        83, ['RB', 'CB'],  'France',      'Inter Milan'),
  p('rb_010', 'Kieran Trippier',        84, ['RB', 'LB'],  'England',     'Newcastle United'),
  p('rb_011', 'Sergiño Dest',           80, ['RB', 'LB'],  'USA',         'PSV Eindhoven'),
  p('rb_012', 'Pedro Porro',            83, ['RB'],        'Spain',       'Tottenham Hotspur'),
  p('rb_013', 'Malo Gusto',             81, ['RB'],        'France',      'Chelsea'),

  // ── CDM (15) ─────────────────────────────────────────────────────────────
  p('cdm_001', 'Casemiro',              88, ['CDM'],          'Brazil',   'Manchester United'),
  p('cdm_002', 'Rodri',                 91, ['CDM'],          'Spain',    'Manchester City'),
  p('cdm_003', 'Fabinho',               87, ['CDM'],          'Brazil',   'Al-Ittihad'),
  p('cdm_004', 'N\'Golo Kanté',         89, ['CDM', 'CM'],    'France',   'Al-Ittihad'),
  p('cdm_005', 'Jorginho',              85, ['CDM', 'CM'],    'Italy',    'Arsenal'),
  p('cdm_006', 'Marcelo Brozović',      85, ['CDM'],          'Croatia',  'Al-Nassr'),
  p('cdm_007', 'Aurélien Tchouaméni',   86, ['CDM'],          'France',   'Real Madrid'),
  p('cdm_008', 'Eduardo Camavinga',     84, ['CDM', 'CM'],    'France',   'Real Madrid'),
  p('cdm_009', 'Thomas Partey',         85, ['CDM'],          'Ghana',    'Arsenal'),
  p('cdm_010', 'Wilfred Ndidi',         83, ['CDM'],          'Nigeria',  'Leicester City'),
  p('cdm_011', 'Sofyan Amrabat',        82, ['CDM'],          'Morocco',  'Fiorentina'),
  p('cdm_012', 'Axel Witsel',           81, ['CDM'],          'Belgium',  'Atlético Madrid'),
  p('cdm_013', 'Sergio Busquets',       86, ['CDM', 'CM'],    'Spain',    'Inter Miami'),
  p('cdm_014', 'Joshua Kimmich',        90, ['CDM', 'CM', 'RB'], 'Germany', 'Bayern Munich'),
  p('cdm_015', 'Declan Rice',           87, ['CDM', 'CM'],    'England',  'Arsenal'),

  // ── CM (16) ──────────────────────────────────────────────────────────────
  p('cm_001', 'Kevin De Bruyne',        91, ['CM', 'CAM'],   'Belgium',   'Manchester City'),
  p('cm_002', 'Luka Modrić',            90, ['CM'],          'Croatia',   'Real Madrid'),
  p('cm_003', 'Toni Kroos',             88, ['CM'],          'Germany',   'Real Madrid'),
  p('cm_004', 'Pedri',                  87, ['CM', 'CAM'],   'Spain',     'FC Barcelona'),
  p('cm_005', 'Gavi',                   87, ['CM'],          'Spain',     'FC Barcelona'),
  p('cm_006', 'Mason Mount',            84, ['CM', 'CAM'],   'England',   'Manchester United'),
  p('cm_007', 'Jordan Henderson',       82, ['CM', 'CDM'],   'England',   'Ajax'),
  p('cm_008', 'Jude Bellingham',        89, ['CM', 'CAM'],   'England',   'Real Madrid'),
  p('cm_009', 'Marco Verratti',         87, ['CM'],          'Italy',     'Al-Arabi'),
  p('cm_010', 'Leon Goretzka',          85, ['CM'],          'Germany',   'Bayern Munich'),
  p('cm_011', 'Mateo Kovačić',          85, ['CM'],          'Croatia',   'Manchester City'),
  p('cm_012', 'Fred',                   81, ['CM', 'CDM'],   'Brazil',    'Fenerbahçe'),
  p('cm_013', 'Thiago Alcântara',       86, ['CM'],          'Spain',     'Liverpool FC'),
  p('cm_014', 'İlkay Gündogan',         86, ['CM', 'CAM'],   'Germany',   'FC Barcelona'),
  p('cm_015', 'Renato Sanches',         82, ['CM'],          'Portugal',  'AS Roma'),
  p('cm_016', 'Conor Gallagher',        82, ['CM'],          'England',   'Atlético Madrid'),

  // ── CAM (14) ─────────────────────────────────────────────────────────────
  p('cam_001', 'Bruno Fernandes',       88, ['CAM', 'CM'],   'Portugal',  'Manchester United'),
  p('cam_002', 'Martin Ødegaard',       88, ['CAM'],         'Norway',    'Arsenal'),
  p('cam_003', 'Phil Foden',            89, ['CAM', 'LW'],   'England',   'Manchester City'),
  p('cam_004', 'James Maddison',        85, ['CAM'],         'England',   'Tottenham Hotspur'),
  p('cam_005', 'Paulo Dybala',          86, ['CAM', 'CF'],   'Argentina', 'AS Roma'),
  p('cam_006', 'Thomas Müller',         85, ['CAM', 'CF'],   'Germany',   'Bayern Munich'),
  p('cam_007', 'Hakim Ziyech',          82, ['CAM', 'RM'],   'Morocco',   'Galatasaray'),
  p('cam_008', 'Kai Havertz',           84, ['CAM', 'CF'],   'Germany',   'Arsenal'),
  p('cam_009', 'Bernardo Silva',        87, ['CAM', 'RM', 'CM'], 'Portugal', 'Manchester City'),
  p('cam_010', 'Isco',                  82, ['CAM', 'CM'],   'Spain',     'Real Betis'),
  p('cam_011', 'Florian Wirtz',         88, ['CAM', 'RM'],   'Germany',   'Bayer Leverkusen'),
  p('cam_012', 'Dries Mertens',         83, ['CAM', 'CF'],   'Belgium',   'Galatasaray'),
  p('cam_013', 'Nabil Fekir',           82, ['CAM', 'LW'],   'France',    'Real Betis'),
  p('cam_014', 'Giovanni Lo Celso',     81, ['CAM', 'CM'],   'Argentina', 'Villarreal'),

  // ── LM (11) ──────────────────────────────────────────────────────────────
  p('lm_001', 'Marcus Rashford',        85, ['LM', 'LW'],   'England',   'Manchester United'),
  p('lm_002', 'Sadio Mané',             87, ['LM', 'LW', 'CF'], 'Senegal', 'Al-Nassr'),
  p('lm_003', 'Raphinha',               85, ['LM', 'RW'],   'Brazil',    'FC Barcelona'),
  p('lm_004', 'Thomas Lemar',           81, ['LM', 'LW'],   'France',    'Atlético Madrid'),
  p('lm_005', 'Ivan Perišić',           83, ['LM', 'LW'],   'Croatia',   'Hajduk Split'),
  p('lm_006', 'Rodrigo de Paul',        83, ['LM', 'CM'],   'Argentina', 'Atlético Madrid'),
  p('lm_007', 'Ángel Di María',         85, ['LM', 'LW', 'RM'], 'Argentina', 'Benfica'),
  p('lm_008', 'Filip Kostić',           82, ['LM', 'LW'],   'Serbia',    'Juventus'),
  p('lm_009', 'Hirving Lozano',         83, ['LM', 'RM', 'LW'], 'Mexico', 'PSV Eindhoven'),
  p('lm_010', 'Harvey Elliott',         80, ['LM', 'CM'],   'England',   'Liverpool FC'),
  p('lm_011', 'Ruben Neves',            84, ['LM', 'CM', 'CDM'], 'Portugal', 'Al-Hilal'),

  // ── RM (11) ──────────────────────────────────────────────────────────────
  p('rm_001', 'Mohamed Salah',          90, ['RM', 'RW'],   'Egypt',     'Liverpool FC'),
  p('rm_002', 'Bukayo Saka',            87, ['RM', 'RW'],   'England',   'Arsenal'),
  p('rm_003', 'Serge Gnabry',           84, ['RM', 'RW', 'LW'], 'Germany', 'Bayern Munich'),
  p('rm_004', 'Antony',                 82, ['RM', 'RW'],   'Brazil',    'Manchester United'),
  p('rm_005', 'Juan Cuadrado',          82, ['RM', 'RW'],   'Colombia',  'Inter Milan'),
  p('rm_006', 'Pedro',                  81, ['RM', 'RW', 'CF'], 'Brazil', 'Lazio'),
  p('rm_007', 'Jesper Lindstrøm',       81, ['RM', 'CAM'],  'Denmark',   'Everton'),
  p('rm_008', 'Arnaut Danjuma',         82, ['RM', 'LW'],   'Netherlands', 'Everton'),
  p('rm_009', 'Jarrod Bowen',           83, ['RM', 'RW'],   'England',   'West Ham'),
  p('rm_010', 'Callum Hudson-Odoi',     79, ['RM', 'RW', 'LW'], 'England', 'Nottingham Forest'),
  p('rm_011', 'Noni Madueke',           80, ['RM', 'RW'],   'England',   'Chelsea'),

  // ── LW (13) ──────────────────────────────────────────────────────────────
  p('lw_001', 'Kylian Mbappé',          92, ['LW', 'ST'],   'France',    'Real Madrid'),
  p('lw_002', 'Neymar Jr',              89, ['LW', 'CAM'],  'Brazil',    'Al-Hilal'),
  p('lw_003', 'Leroy Sané',             87, ['LW', 'RW'],   'Germany',   'Bayern Munich'),
  p('lw_004', 'Vinícius Júnior',        90, ['LW'],         'Brazil',    'Real Madrid'),
  p('lw_005', 'Ousmane Dembélé',        86, ['LW', 'RW'],   'France',    'Paris Saint-Germain'),
  p('lw_006', 'Raheem Sterling',        84, ['LW', 'RW'],   'England',   'Chelsea'),
  p('lw_007', 'Ansu Fati',             83, ['LW'],         'Spain',     'FC Barcelona'),
  p('lw_008', 'Adama Traoré',           81, ['LW', 'RW'],   'Spain',     'Wolverhampton'),
  p('lw_009', 'Dejan Kulusevski',       84, ['LW', 'RM'],   'Sweden',    'Tottenham Hotspur'),
  p('lw_010', 'Memphis Depay',          84, ['LW', 'CF'],   'Netherlands', 'Atlético Madrid'),
  p('lw_011', 'Federico Chiesa',        84, ['LW', 'RW'],   'Italy',     'Liverpool FC'),
  p('lw_012', 'Rafael Leão',            87, ['LW'],         'Portugal',  'AC Milan'),
  p('lw_013', 'Jonathan David',         86, ['LW', 'ST', 'CF'], 'Canada', 'LOSC Lille'),

  // ── RW (13) ──────────────────────────────────────────────────────────────
  p('rw_001', 'Lionel Messi',           91, ['RW', 'CAM'],  'Argentina', 'Inter Miami'),
  p('rw_002', 'Son Heung-min',          89, ['RW', 'LW'],   'South Korea', 'Tottenham Hotspur'),
  p('rw_003', 'Jadon Sancho',           84, ['RW', 'LW'],   'England',   'Borussia Dortmund'),
  p('rw_004', 'Riyad Mahrez',           86, ['RW', 'LW'],   'Algeria',   'Al-Ahli'),
  p('rw_005', 'Christian Pulisic',      82, ['RW', 'LW', 'CAM'], 'USA', 'AC Milan'),
  p('rw_006', 'Wilfried Zaha',          83, ['RW', 'LW'],   'Ivory Coast', 'Galatasaray'),
  p('rw_007', 'Lorenzo Insigne',        83, ['RW', 'LW'],   'Italy',     'Toronto FC'),
  p('rw_008', 'Ademola Lookman',        84, ['RW', 'LW'],   'Nigeria',   'Atalanta'),
  p('rw_009', 'Harvey Barnes',          83, ['RW', 'LW'],   'England',   'Newcastle United'),
  p('rw_010', 'Reiss Nelson',           80, ['RW', 'LW'],   'England',   'Arsenal'),
  p('rw_011', 'Bryan Gil',              79, ['RW', 'LW'],   'Spain',     'UD Almería'),
  p('rw_012', 'Lamine Yamal',           82, ['RW', 'LW'],   'Spain',     'FC Barcelona'),
  p('rw_013', 'Eberechi Eze',           84, ['RW', 'CAM'],  'England',   'Crystal Palace'),

  // ── CF (11) ──────────────────────────────────────────────────────────────
  p('cf_001', 'Roberto Firmino',        84, ['CF', 'ST'],   'Brazil',    'Al-Ahli'),
  p('cf_002', 'Antoine Griezmann',      87, ['CF', 'CAM'],  'France',    'Atlético Madrid'),
  p('cf_003', 'Romelu Lukaku',          86, ['CF', 'ST'],   'Belgium',   'AS Roma'),
  p('cf_004', 'Diogo Jota',             86, ['CF', 'LW'],   'Portugal',  'Liverpool FC'),
  p('cf_005', 'Aleksandar Mitrović',    85, ['CF', 'ST'],   'Serbia',    'Al-Hilal'),
  p('cf_006', 'Alexandre Lacazette',    82, ['CF', 'ST'],   'France',    'Olympique Lyonnais'),
  p('cf_007', 'Edinson Cavani',         83, ['CF', 'ST'],   'Uruguay',   'Boca Juniors'),
  p('cf_008', 'Timo Werner',            81, ['CF', 'LW'],   'Germany',   'Tottenham Hotspur'),
  p('cf_009', 'Olivier Giroud',         82, ['CF', 'ST'],   'France',    'LA Galaxy'),
  p('cf_010', 'Álvaro Morata',          83, ['CF', 'ST'],   'Spain',     'Atlético Madrid'),
  p('cf_011', 'Lorenzo Pellegrini',     84, ['CF', 'CAM'],  'Italy',     'AS Roma'),

  // ── ST (14) ──────────────────────────────────────────────────────────────
  p('st_001', 'Erling Haaland',         92, ['ST'],         'Norway',    'Manchester City'),
  p('st_002', 'Harry Kane',             91, ['ST', 'CF'],   'England',   'Bayern Munich'),
  p('st_003', 'Victor Osimhen',         89, ['ST'],         'Nigeria',   'Galatasaray'),
  p('st_004', 'Karim Benzema',          90, ['ST', 'CF'],   'France',    'Al-Ittihad'),
  p('st_005', 'Robert Lewandowski',     90, ['ST'],         'Poland',    'FC Barcelona'),
  p('st_006', 'Cristiano Ronaldo',      87, ['ST', 'LW'],   'Portugal',  'Al-Nassr'),
  p('st_007', 'Dušan Vlahović',         86, ['ST'],         'Serbia',    'Juventus'),
  p('st_008', 'Darwin Núñez',           85, ['ST', 'CF'],   'Uruguay',   'Liverpool FC'),
  p('st_009', 'Tammy Abraham',          83, ['ST', 'CF'],   'England',   'AC Milan'),
  p('st_010', 'Rasmus Højlund',         84, ['ST'],         'Denmark',   'Manchester United'),
  p('st_011', 'Ollie Watkins',          84, ['ST', 'CF'],   'England',   'Aston Villa'),
  p('st_012', 'Wout Weghorst',          81, ['ST'],         'Netherlands', 'Burnley'),
  p('st_013', 'Ivan Toney',             84, ['ST'],         'England',   'Al-Ahli'),
  p('st_014', 'Patson Daka',            82, ['ST', 'CF'],   'Zambia',    'Leicester City'),
];
