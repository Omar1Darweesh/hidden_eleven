import { Params } from 'nestjs-pino';

/**
 * Shared so AppModule, RoomsModule, and GameModule all register the exact
 * same pino config — pretty-printed, colorized, human-readable output in
 * development; plain newline-delimited JSON in production (the format a log
 * aggregator/shipper actually wants). Detected via NODE_ENV, matching the
 * same convention already used by assertProductionSecretsConfigured() in
 * main.ts.
 */
export const LOGGER_CONFIG: Params = {
  pinoHttp: {
    level: process.env.NODE_ENV === 'production' ? 'info' : 'debug',
    transport:
      process.env.NODE_ENV === 'production'
        ? undefined
        : {
            target: 'pino-pretty',
            options: { colorize: true, singleLine: true, translateTime: 'HH:MM:ss' },
          },
  },
};
