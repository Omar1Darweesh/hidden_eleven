import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import { ValidationPipe } from '@nestjs/common';
import { Logger, PinoLogger } from 'nestjs-pino';
import { join } from 'path';
import compression from 'compression';
import helmet from 'helmet';
import { AppModule } from './app.module.js';
import { IdStampingWsAdapter } from './ws-adapter.js';
import { getAllowedOrigins } from './cors-origins.js';
import { HttpExceptionFilter } from './shared/http-exception.filter.js';
import { LOGGER_CONFIG } from './shared/logger-config.js';
import { RoomsGateway } from './rooms/rooms.gateway.js';
import { ServerState } from './shared/server-state.service.js';

const SHUTDOWN_DRAIN_MS = 5000;

function assertProductionSecretsConfigured(): void {
  if (process.env.NODE_ENV !== 'production') return;
  if (!process.env.RECONNECT_TOKEN_SECRET || process.env.RECONNECT_TOKEN_SECRET.trim() === '') {
    throw new Error(
      'RECONNECT_TOKEN_SECRET must be set in production — refusing to start. ' +
        'See .env.example for how to generate one.',
    );
  }
  if (!process.env.ADMIN_API_KEY || process.env.ADMIN_API_KEY.trim() === '') {
    throw new Error(
      'ADMIN_API_KEY must be set in production — refusing to start. ' +
        'See .env.example for how to generate one.',
    );
  }
  const origins = process.env.ALLOWED_ORIGINS?.trim() ?? '';
  if (!origins || origins === 'http://localhost:3000') {
    throw new Error(
      'ALLOWED_ORIGINS must be set to your production HTTPS domain(s) — ' +
        'refusing to start with the localhost-only default.',
    );
  }
}

async function bootstrap() {
  assertProductionSecretsConfigured();
  // bufferLogs holds Nest's own startup logs (DI wiring, route mapping, etc.)
  // until useLogger() below swaps in pino — otherwise they'd print via Nest's
  // default console logger and never go through pino at all.
  const app = await NestFactory.create<NestExpressApplication>(AppModule, { bufferLogs: true });
  app.useLogger(app.get(Logger));
  const wsAdapter = new IdStampingWsAdapter(app);
  wsAdapter.setLogger(app.get(Logger));
  app.useWebSocketAdapter(wsAdapter);
  // Must come before enableCors() — helmet sets several headers (including a
  // default Cross-Origin-Resource-Policy) that can suppress or conflict with
  // CORS headers if applied after them.
  //
  // contentSecurityPolicy is explicitly disabled — verified live (started
  // the real server, fetched the actual built index.html) that helmet's
  // default CSP (script-src 'self', no 'unsafe-inline'/'wasm-unsafe-eval')
  // would break the Flutter web app this server serves at `/`: the build's
  // index.html has a real inline <script> (clears a stale service worker on
  // load) that a default CSP blocks outright, and Flutter's CanvasKit
  // renderer needs WASM execution a strict script-src also disallows.
  // Getting a CSP that's both meaningful and compatible with Flutter web's
  // bootstrap would need careful, browser-verified tuning per renderer mode —
  // a separate, focused piece of work, not a one-line helmet() call. Every
  // other helmet protection (HSTS, X-Frame-Options, X-Content-Type-Options,
  // Referrer-Policy, etc.) is unaffected by this and stays enabled.
  app.use(helmet({ contentSecurityPolicy: false }));
  // Covers the HTTP admin API's @Body() DTOs. NOTE: this does NOT reach
  // RoomsGateway's WebSocket @MessageBody() params in practice — verified
  // live that @nestjs/platform-ws doesn't consult globally-registered pipes
  // the same way HTTP does, so RoomsGateway carries its own identical
  // @UsePipes(new ValidationPipe(...)) at the class level instead (see
  // rooms.gateway.ts). whitelist+forbidNonWhitelisted reject any payload
  // carrying fields the DTO doesn't declare (not just strip them), so a
  // malformed/extended payload fails loudly instead of being silently
  // truncated. transform applies @Type()/primitive coercion (e.g. numeric
  // strings → number) before the handler ever sees the DTO.
  app.useGlobalPipes(
    new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }),
  );
  // Admin REST API only — see http-exception.filter.ts for why it no-ops on
  // the WebSocket side.
  app.useGlobalFilters(new HttpExceptionFilter());
  // Restricted to ALLOWED_ORIGINS (env, comma-separated) — defaults to
  // localhost:3000 for local dev. See cors-origins.ts.
  app.enableCors({ origin: getAllowedOrigins() });

  // gzip every response. The Flutter web bundle (main.dart.js, canvaskit, etc.)
  // is highly compressible — typically a ~75% transfer reduction. This both
  // speeds up loads and dramatically lowers tunnel bandwidth usage (e.g. ngrok's
  // free monthly quota), which is the main cost driver when reloading the app.
  app.use(compression());

  // Serve static assets (player photos, club logos, flags, etc.)
  const assetsRoot = join(process.cwd(), 'assets');
  app.useStaticAssets(assetsRoot, { prefix: '/assets' });

  // Serve Flutter web build at root so one port handles everything.
  //
  // Cache strategy is split to balance "edits show up instantly" against tunnel
  // bandwidth cost:
  //   • App code & shell (index.html, *.dart.js, flutter_bootstrap.js, manifest)
  //     → no-store, so every rebuild is picked up immediately on reload.
  //   • Heavy immutable engine assets (canvaskit/, *.wasm, fonts/, *.otf/.ttf,
  //     and bundled asset images) → cached for a day, since they never change
  //     between code edits. This avoids re-downloading ~MBs of CanvasKit + fonts
  //     on every reload, which is what exhausts ngrok's free monthly quota.
  const webRoot = join(process.cwd(), '..', 'hidden_eleven', 'build', 'web');
  const immutableAsset =
    /(?:\.(?:wasm|otf|ttf|woff2?|png|jpg|jpeg|webp|gif|symbols)$|\/canvaskit\/|\/fonts\/)/i;
  app.useStaticAssets(webRoot, {
    prefix: '/',
    setHeaders: (res, path) => {
      if (immutableAsset.test(path)) {
        res.setHeader('Cache-Control', 'public, max-age=86400');
      } else {
        res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
      }
    },
  });

  const port = process.env.PORT ?? 3000;
  // '::' (IPv6 wildcard), not '0.0.0.0' — on Windows dev machines, ngrok's
  // agent dials the upstream via IPv6 loopback ([::1]) specifically. Binding
  // only the IPv4 wildcard left that connection "actively refused" even
  // though the server was healthy and reachable on 127.0.0.1/localhost the
  // whole time — a genuinely confusing failure mode since curl and a browser
  // hitting localhost both worked. Dual-stack sockets (the default on
  // Windows/Linux/macOS unless IPV6_V6ONLY is explicitly set) mean binding
  // '::' also accepts IPv4 connections, so this covers both without a
  // second listen() call.
  await app.listen(port, '::');
  // nestjs-pino's `Logger` (used above for useLogger()) implements Nest's
  // standard LoggerService contract — log(message, context?), a STRING
  // context label, not a structured object. It's the right tool for routing
  // Nest's own framework logs through pino, but the wrong one for a
  // genuinely structured app log line, which is what's wanted here — so a
  // plain PinoLogger (same config, its own 'Bootstrap' context) is used
  // instead, matching the (obj, msg) convention used everywhere else in this
  // codebase (rooms.gateway.ts, rooms.service.ts, game.service.ts).
  const bootstrapLogger = new PinoLogger(LOGGER_CONFIG);
  bootstrapLogger.setContext('Bootstrap');
  bootstrapLogger.info({ port }, 'Hidden Eleven server running');

  // Graceful shutdown — deliberately a manual SIGTERM listener rather than
  // app.enableShutdownHooks() (which would register Nest's own signal
  // handler and call app.close() immediately on receipt): this needs to
  // warn connected clients and wait out a drain window *before* tearing the
  // app down, not on the same tick the signal arrives.
  let shuttingDown = false;
  process.on('SIGTERM', () => {
    if (shuttingDown) return;
    shuttingDown = true;
    void (async () => {
      bootstrapLogger.info({}, 'SIGTERM received — starting graceful shutdown');

      // 0. Flip the liveness flag first, before anything else, so /health
      // (Task 3.4) starts reporting 503 as early in the drain window as
      // possible — a load balancer or PM2's own health_check_http polling
      // this gets the earliest possible signal to stop routing here.
      app.get(ServerState).markShuttingDown();

      // 1. Stop accepting new connections. Node's http.Server.close() only
      // refuses new connections/upgrade requests — it does not terminate
      // already-open sockets (including already-upgraded WebSocket
      // connections, which have left the HTTP request/response cycle
      // entirely), so existing players are unaffected by this step.
      app.getHttpServer().close();

      // 2. Warn every currently-connected socket.
      app.get(RoomsGateway).broadcastShutdownWarning();

      // 3. Give in-flight messages time to be sent/received before sockets
      // start getting force-closed by step 4.
      await new Promise((resolve) => setTimeout(resolve, SHUTDOWN_DRAIN_MS));

      // 4. Full app shutdown — runs onModuleDestroy (timer cleanup) then
      // onApplicationShutdown (closes any sockets still open) on every
      // provider that implements them, see rooms.gateway.ts.
      bootstrapLogger.info({}, 'Drain window elapsed — closing application');
      await app.close();
      process.exit(0);
    })();
  });
}
bootstrap();
