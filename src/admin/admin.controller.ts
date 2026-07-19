import {
  Controller,
  Get,
  Post,
  Put,
  Delete,
  Body,
  Param,
  Query,
  Res,
  HttpCode,
  HttpStatus,
  UseInterceptors,
  UseGuards,
  UploadedFile,
  ParseFilePipe,
  MaxFileSizeValidator,
  FileTypeValidator,
  BadRequestException,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ThrottlerGuard, Throttle, seconds } from '@nestjs/throttler';
import { InjectPinoLogger, PinoLogger } from 'nestjs-pino';
import type { Response } from 'express';
import * as https from 'https';
import { AdminService } from './admin.service.js';
import { AdminAuthGuard } from '../shared/admin-auth.guard.js';
import { CreatePlayerDto, UpdatePlayerDto } from './dto/admin-player.dto.js';
import {
  CreateClubDto,
  UpdateClubDto,
  CreateNationDto,
  UpdateNationDto,
  CreateLeagueDto,
  UpdateLeagueDto,
  CreateLeagueBundleDto,
  UpdateLeagueBundleDto,
  CreateCardTierDto,
  UpdateCardTierDto,
  UpdateAbilityDto,
} from './dto/admin-catalog.dto.js';
import {
  CreateFormationDto,
  UpdateFormationDto,
} from './dto/admin-formation.dto.js';
import {
  UpdateGuideSectionDto,
  CreateFaqDto,
  UpdateFaqDto,
  CreateQuickTipDto,
  UpdateQuickTipDto,
  UpdateContextHelpDto,
} from './dto/admin-content.dto.js';
import {
  SaveScoringConfigDraftDto,
  PublishScoringConfigDto,
} from './dto/admin-scoring.dto.js';
import {
  SaveTournamentAwardsConfigDraftDto,
  PublishTournamentAwardsConfigDto,
} from './dto/admin-tournament-awards.dto.js';

// Allowed CDN hosts for the image proxy (allowlist to prevent open proxy abuse)
const ALLOWED_IMAGE_HOSTS = new Set([
  'cdn.sofifa.net',
  'media.api-sports.io',
  'a.espncdn.com',
  'flagcdn.com',
]);

const MAX_FILE_SIZE = 5 * 1024 * 1024; // 5 MB
const IMAGE_MIME_RE = /^image\/(jpeg|png|webp|gif|svg\+xml)$/;

const imageFilePipe = new ParseFilePipe({
  validators: [
    new MaxFileSizeValidator({ maxSize: MAX_FILE_SIZE }),
    new FileTypeValidator({ fileType: IMAGE_MIME_RE }),
  ],
});

// Upstream image fetch must never hang indefinitely — a slow/stalled CDN
// response would otherwise tie up a connection (and this endpoint has no
// auth) for as long as the upstream keeps the socket open.
const IMAGE_PROXY_TIMEOUT_MS = 5000;
const IMAGE_PROXY_MAX_BYTES = 6 * 1024 * 1024; // 6 MB — above 5 MB upload cap, below abuse size

/**
 * Every route here inherits the shared 'default' throttler (30 req/10s per
 * IP, see throttler-config.ts) via the module-level ThrottlerModule import —
 * a sane baseline for human-paced admin-panel CRUD. This is separate from,
 * and doesn't affect, RoomsGateway's own WsThrottlerGuard on the WebSocket
 * side, or HealthController (different module, no guard applied — /health
 * and /metrics must stay reachable for PM2/monitoring without a rate limit).
 */
@UseGuards(ThrottlerGuard)
@Controller('api/admin')
export class AdminController {
  constructor(
    private readonly adminService: AdminService,
    @InjectPinoLogger(AdminController.name)
    private readonly logger: PinoLogger = new PinoLogger({ pinoHttp: { level: 'silent' } }),
  ) {}

  // ── Players ─────────────────────────────────────────────────────────────────

  @UseGuards(AdminAuthGuard)
  @Get('players')
  getPlayers() {
    return this.adminService.getPlayers();
  }

  @UseGuards(AdminAuthGuard)
  @Post('players')
  createPlayer(@Body() dto: CreatePlayerDto) {
    return this.adminService.createPlayer(dto);
  }

  @UseGuards(AdminAuthGuard)
  @Get('players/:id')
  getPlayer(@Param('id') id: string) {
    return this.adminService.getPlayer(id);
  }

  @UseGuards(AdminAuthGuard)
  @Put('players/:id')
  updatePlayer(@Param('id') id: string, @Body() dto: UpdatePlayerDto) {
    return this.adminService.updatePlayer(id, dto);
  }

  @UseGuards(AdminAuthGuard)
  @Delete('players/:id')
  @HttpCode(HttpStatus.NO_CONTENT)
  deletePlayer(@Param('id') id: string) {
    this.adminService.deletePlayer(id);
  }

  @UseGuards(AdminAuthGuard)
  @Post('upload/player-photo/:id')
  @UseInterceptors(FileInterceptor('file'))
  uploadPlayerPhoto(
    @Param('id') id: string,
    @UploadedFile(imageFilePipe) file: Express.Multer.File,
  ) {
    return this.adminService.uploadPlayerPhoto(id, file);
  }

  // ── Clubs ────────────────────────────────────────────────────────────────────

  @UseGuards(AdminAuthGuard)
  @Get('clubs')
  getClubs() {
    return this.adminService.getClubs();
  }

  @UseGuards(AdminAuthGuard)
  @Post('clubs')
  createClub(@Body() dto: CreateClubDto) {
    return this.adminService.createClub(dto);
  }

  @UseGuards(AdminAuthGuard)
  @Get('clubs/:slug')
  getClub(@Param('slug') slug: string) {
    return this.adminService.getClub(slug);
  }

  @UseGuards(AdminAuthGuard)
  @Put('clubs/:slug')
  updateClub(@Param('slug') slug: string, @Body() dto: UpdateClubDto) {
    return this.adminService.updateClub(slug, dto);
  }

  @UseGuards(AdminAuthGuard)
  @Delete('clubs/:slug')
  @HttpCode(HttpStatus.NO_CONTENT)
  deleteClub(@Param('slug') slug: string) {
    this.adminService.deleteClub(slug);
  }

  @UseGuards(AdminAuthGuard)
  @Post('upload/club-logo/:slug')
  @UseInterceptors(FileInterceptor('file'))
  uploadClubLogo(
    @Param('slug') slug: string,
    @UploadedFile(imageFilePipe) file: Express.Multer.File,
  ) {
    return this.adminService.uploadClubLogo(slug, file);
  }

  // ── Nations ──────────────────────────────────────────────────────────────────

  @UseGuards(AdminAuthGuard)
  @Get('nations')
  getNations() {
    return this.adminService.getNations();
  }

  @UseGuards(AdminAuthGuard)
  @Post('nations')
  createNation(@Body() dto: CreateNationDto) {
    return this.adminService.createNation(dto);
  }

  @UseGuards(AdminAuthGuard)
  @Get('nations/:slug')
  getNation(@Param('slug') slug: string) {
    return this.adminService.getNation(slug);
  }

  @UseGuards(AdminAuthGuard)
  @Put('nations/:slug')
  updateNation(@Param('slug') slug: string, @Body() dto: UpdateNationDto) {
    return this.adminService.updateNation(slug, dto);
  }

  @UseGuards(AdminAuthGuard)
  @Delete('nations/:slug')
  @HttpCode(HttpStatus.NO_CONTENT)
  deleteNation(@Param('slug') slug: string) {
    this.adminService.deleteNation(slug);
  }

  @UseGuards(AdminAuthGuard)
  @Post('upload/nation-flag/:slug')
  @UseInterceptors(FileInterceptor('file'))
  uploadNationFlag(
    @Param('slug') slug: string,
    @UploadedFile(imageFilePipe) file: Express.Multer.File,
  ) {
    return this.adminService.uploadNationFlag(slug, file);
  }

  // ── Leagues ──────────────────────────────────────────────────────────────────

  @Get('leagues')
  getLeagues() {
    return this.adminService.getLeagues();
  }

  @UseGuards(AdminAuthGuard)
  @Post('leagues')
  createLeague(@Body() dto: CreateLeagueDto) {
    return this.adminService.createLeague(dto);
  }

  @UseGuards(AdminAuthGuard)
  @Get('leagues/:slug')
  getLeague(@Param('slug') slug: string) {
    return this.adminService.getLeague(slug);
  }

  @UseGuards(AdminAuthGuard)
  @Put('leagues/:slug')
  updateLeague(@Param('slug') slug: string, @Body() dto: UpdateLeagueDto) {
    return this.adminService.updateLeague(slug, dto);
  }

  @UseGuards(AdminAuthGuard)
  @Delete('leagues/:slug')
  @HttpCode(HttpStatus.NO_CONTENT)
  deleteLeague(@Param('slug') slug: string) {
    this.adminService.deleteLeague(slug);
  }

  @UseGuards(AdminAuthGuard)
  @Post('upload/league-logo/:slug')
  @UseInterceptors(FileInterceptor('file'))
  uploadLeagueLogo(
    @Param('slug') slug: string,
    @UploadedFile(imageFilePipe) file: Express.Multer.File,
  ) {
    return this.adminService.uploadLeagueLogo(slug, file);
  }

  // ── League bundles ─────────────────────────────────────────────────────────

  /** Admin list (all bundles). Public read, same pattern as leagues. */
  @Get('league-bundles')
  getLeagueBundles() {
    return this.adminService.getLeagueBundles();
  }

  /** Host picker: active bundles only, with league name/logo preview. */
  @Get('league-bundles/active')
  getActiveLeagueBundles() {
    return this.adminService.getActiveLeagueBundles();
  }

  @UseGuards(AdminAuthGuard)
  @Post('league-bundles')
  createLeagueBundle(@Body() dto: CreateLeagueBundleDto) {
    return this.adminService.createLeagueBundle(dto);
  }

  @UseGuards(AdminAuthGuard)
  @Get('league-bundles/:id')
  getLeagueBundle(@Param('id') id: string) {
    return this.adminService.getLeagueBundle(id);
  }

  @UseGuards(AdminAuthGuard)
  @Put('league-bundles/:id')
  updateLeagueBundle(
    @Param('id') id: string,
    @Body() dto: UpdateLeagueBundleDto,
  ) {
    return this.adminService.updateLeagueBundle(id, dto);
  }

  @UseGuards(AdminAuthGuard)
  @Post('league-bundles/:id/duplicate')
  duplicateLeagueBundle(@Param('id') id: string) {
    return this.adminService.duplicateLeagueBundle(id);
  }

  @UseGuards(AdminAuthGuard)
  @Delete('league-bundles/:id')
  @HttpCode(HttpStatus.NO_CONTENT)
  deleteLeagueBundle(@Param('id') id: string) {
    this.adminService.deleteLeagueBundle(id);
  }

  // ── Formations ─────────────────────────────────────────────────────────────────

  @Get('formations')
  getFormations() {
    return this.adminService.getFormations();
  }

  @UseGuards(AdminAuthGuard)
  @Post('formations')
  createFormation(@Body() dto: CreateFormationDto) {
    return this.adminService.createFormation(dto);
  }

  @UseGuards(AdminAuthGuard)
  @Get('formations/:slug')
  getFormation(@Param('slug') slug: string) {
    return this.adminService.getFormation(slug);
  }

  @UseGuards(AdminAuthGuard)
  @Put('formations/:slug')
  updateFormation(
    @Param('slug') slug: string,
    @Body() dto: UpdateFormationDto,
  ) {
    return this.adminService.updateFormation(slug, dto);
  }

  @UseGuards(AdminAuthGuard)
  @Delete('formations/:slug')
  @HttpCode(HttpStatus.NO_CONTENT)
  deleteFormation(@Param('slug') slug: string) {
    this.adminService.deleteFormation(slug);
  }

  // ── Card tiers ─────────────────────────────────────────────────────────────────

  @Get('card-tiers')
  getCardTiers() {
    return this.adminService.getCardTiers();
  }

  @UseGuards(AdminAuthGuard)
  @Post('card-tiers')
  createCardTier(@Body() dto: CreateCardTierDto) {
    return this.adminService.createCardTier(dto);
  }

  @UseGuards(AdminAuthGuard)
  @Put('card-tiers/:slug')
  updateCardTier(
    @Param('slug') slug: string,
    @Body() dto: UpdateCardTierDto,
  ) {
    return this.adminService.updateCardTier(slug, dto);
  }

  @UseGuards(AdminAuthGuard)
  @Delete('card-tiers/:slug')
  @HttpCode(HttpStatus.NO_CONTENT)
  deleteCardTier(@Param('slug') slug: string) {
    this.adminService.deleteCardTier(slug);
  }

  // ── Abilities ────────────────────────────────────────────────────────────────

  @Get('abilities')
  getAbilities() {
    return this.adminService.getAbilities();
  }

  @UseGuards(AdminAuthGuard)
  @Put('abilities/:type')
  updateAbility(@Param('type') type: string, @Body() dto: UpdateAbilityDto) {
    return this.adminService.updateAbility(type, dto);
  }

  // ── Scoring config ─────────────────────────────────────────────────────────────
  // Draft shape is enforced by SaveScoringConfigDraftDto (ValidationPipe).
  // Publish-time semantic ranges still live in validateScoringConfigValues
  // inside AdminService.publishScoringConfig.

  // Player-facing read — published values only (no draft/history leak).
  @Get('scoring-config/published')
  getPublishedScoringConfig() {
    return this.adminService.getScoringConfig().published;
  }

  @UseGuards(AdminAuthGuard)
  @Get('scoring-config')
  getScoringConfig() {
    return this.adminService.getScoringConfig();
  }

  @UseGuards(AdminAuthGuard)
  @Put('scoring-config/draft')
  saveScoringConfigDraft(@Body() values: SaveScoringConfigDraftDto) {
    return this.adminService.saveScoringConfigDraft(values);
  }

  @UseGuards(AdminAuthGuard)
  @Post('scoring-config/publish')
  publishScoringConfig(@Body() dto: PublishScoringConfigDto) {
    return this.adminService.publishScoringConfig(dto?.note);
  }

  // ── Tournament awards config (Track A Step 2 — routes only, no gameplay
  // wiring yet) ──────────────────────────────────────────────────────────────
  // Draft shape is enforced by SaveTournamentAwardsConfigDraftDto
  // (ValidationPipe). Publish-time semantic ranges still live in
  // validateTournamentAwardsConfigValues inside
  // AdminService.publishTournamentAwardsConfig. Same guard split as scoring
  // config above.

  // Player-facing read — published values only (no draft/history leak).
  @Get('tournament-awards-config/published')
  getPublishedTournamentAwardsConfig() {
    return this.adminService.getTournamentAwardsConfig().published;
  }

  @UseGuards(AdminAuthGuard)
  @Get('tournament-awards-config')
  getTournamentAwardsConfig() {
    return this.adminService.getTournamentAwardsConfig();
  }

  @UseGuards(AdminAuthGuard)
  @Put('tournament-awards-config/draft')
  saveTournamentAwardsConfigDraft(@Body() values: SaveTournamentAwardsConfigDraftDto) {
    return this.adminService.saveTournamentAwardsConfigDraft(values);
  }

  @UseGuards(AdminAuthGuard)
  @Post('tournament-awards-config/publish')
  publishTournamentAwardsConfig(@Body() dto: PublishTournamentAwardsConfigDto) {
    return this.adminService.publishTournamentAwardsConfig(dto?.note);
  }

  // ── Guide sections (Instructions / Game Guide) ────────────────────────────────

  @Get('guide-sections')
  getGuideSections() {
    return this.adminService.getGuideSections();
  }

  @UseGuards(AdminAuthGuard)
  @Put('guide-sections/:key')
  updateGuideSection(
    @Param('key') key: string,
    @Body() dto: UpdateGuideSectionDto,
  ) {
    return this.adminService.updateGuideSection(key, dto);
  }

  // ── FAQ ────────────────────────────────────────────────────────────────────────

  @Get('faq')
  getFaqItems() {
    return this.adminService.getFaqItems();
  }

  @UseGuards(AdminAuthGuard)
  @Post('faq')
  createFaqItem(@Body() dto: CreateFaqDto) {
    return this.adminService.createFaqItem(dto);
  }

  @UseGuards(AdminAuthGuard)
  @Put('faq/:id')
  updateFaqItem(@Param('id') id: string, @Body() dto: UpdateFaqDto) {
    return this.adminService.updateFaqItem(id, dto);
  }

  @UseGuards(AdminAuthGuard)
  @Delete('faq/:id')
  @HttpCode(HttpStatus.NO_CONTENT)
  deleteFaqItem(@Param('id') id: string) {
    this.adminService.deleteFaqItem(id);
  }

  // ── Quick tips ───────────────────────────────────────────────────────────────

  @Get('quick-tips')
  getQuickTips() {
    return this.adminService.getQuickTips();
  }

  @UseGuards(AdminAuthGuard)
  @Post('quick-tips')
  createQuickTip(@Body() dto: CreateQuickTipDto) {
    return this.adminService.createQuickTip(dto);
  }

  @UseGuards(AdminAuthGuard)
  @Put('quick-tips/:id')
  updateQuickTip(@Param('id') id: string, @Body() dto: UpdateQuickTipDto) {
    return this.adminService.updateQuickTip(id, dto);
  }

  @UseGuards(AdminAuthGuard)
  @Delete('quick-tips/:id')
  @HttpCode(HttpStatus.NO_CONTENT)
  deleteQuickTip(@Param('id') id: string) {
    this.adminService.deleteQuickTip(id);
  }

  // ── Context help (in-app "?" dialogs) ─────────────────────────────────────────

  @Get('context-help')
  getContextHelp() {
    return this.adminService.getContextHelp();
  }

  @UseGuards(AdminAuthGuard)
  @Put('context-help/:key')
  updateContextHelp(
    @Param('key') key: string,
    @Body() dto: UpdateContextHelpDto,
  ) {
    return this.adminService.updateContextHelp(key, dto);
  }

  // ── Assets ───────────────────────────────────────────────────────────────────

  @UseGuards(AdminAuthGuard)
  @Get('assets')
  getAssets() {
    return this.adminService.getAssetTree();
  }

  // ── Image proxy (bypasses CORS for allowlisted CDNs on Flutter web) ──────────

  /**
   * Tighter than the controller's ambient 30/10s baseline: this is the one
   * admin route that triggers an outbound network request per call (the
   * others just read/write local JSON), so it's the one worth capping harder
   * against a flood. 20/10s per IP still comfortably covers a real screen
   * rendering a full squad's worth of photos/flags in one paint — Flutter's
   * image cache means each distinct URL is only fetched once per session,
   * not on every rebuild.
   */
  @Throttle({ default: { limit: 20, ttl: seconds(10) } })
  @Get('proxy/image')
  proxyImage(@Query('url') url: string, @Res() res: Response) {
    if (!url) throw new BadRequestException('url is required');

    let parsed: URL;
    try {
      parsed = new URL(url);
    } catch {
      throw new BadRequestException('invalid url');
    }

    if (!ALLOWED_IMAGE_HOSTS.has(parsed.hostname)) {
      throw new BadRequestException('host not allowed');
    }

    if (parsed.protocol !== 'https:') {
      throw new BadRequestException('only https upstream URLs are allowed');
    }

    const upstreamReq = https.get(url, { timeout: IMAGE_PROXY_TIMEOUT_MS }, (upstream) => {
      const contentType = upstream.headers['content-type'] ?? 'image/jpeg';
      if (!/^image\//i.test(contentType)) {
        upstream.resume();
        if (!res.headersSent) res.status(502).end();
        return;
      }
      res.setHeader('Content-Type', contentType);
      res.setHeader('Cache-Control', 'public, max-age=86400');
      let bytes = 0;
      upstream.on('data', (chunk: Buffer) => {
        bytes += chunk.length;
        if (bytes > IMAGE_PROXY_MAX_BYTES) {
          upstream.destroy();
          if (!res.headersSent) res.status(502).end();
        }
      });
      upstream.pipe(res);
    });

    // The `timeout` option above only arms a socket-idle timer — Node still
    // requires an explicit 'timeout' listener to actually abort the request;
    // without one the socket timer fires but the request hangs open anyway.
    // destroy() below triggers the shared 'error' handler exactly once, so
    // the 502 response is only ever sent from one place.
    upstreamReq.on('timeout', () => {
      upstreamReq.destroy(new Error('upstream image request timed out'));
    });

    upstreamReq.on('error', (err) => {
      this.logger.warn({ url, hostname: parsed.hostname, err: err.message }, 'Image proxy upstream request failed');
      if (!res.headersSent) res.status(502).end();
    });
  }
}
