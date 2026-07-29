import { runMercuryCli } from './composition/cli.ts';

/** Public product identifier. */
export const mercuryProduct = 'mercury.webhook' as const;

export {
  createMercuryApplication,
  defaultSecretReferences,
  LocalCircuitCommander,
  LocalReplayDispatcher,
  LoggingConsoleIncidentReporter,
  localLandscapeTopology,
  ManagementReplayAuditor,
  type MercuryAppleBackfillSeam,
  type MercuryApplication,
  type MercuryCompositionSeams,
  type MercuryDbInitResult,
  type MercuryGoogleRtdnSeam,
  type MercurySecretReferences,
  type MercuryServerFactory,
  type MercuryServerHandle,
  type MercuryServerOptions,
  runMercuryDbInit,
} from './composition/application.ts';
export {
  MERCURY_USAGE,
  type MercuryCliOptions,
  type MercuryCliSignals,
  type MercuryCommand,
  mercuryCommands,
  redactDiagnostic,
  runMercuryCli,
} from './composition/cli.ts';
export {
  loadMercuryConfig,
  loadMercuryConfigResult,
  type MercuryConfig,
  type MercuryConfigLoadOptions,
} from './composition/config.ts';
export type { MercuryDependencyState, MercuryReadinessReport } from './composition/http.ts';
export {
  createMercuryTestStack,
  MercurySitClientError,
  type MercuryTestStack,
  type MercuryTestStackFactoryInput,
  type ProviderName,
} from './sit/index.ts';

if (import.meta.main) {
  process.exit(await runMercuryCli(process.argv.slice(2)));
}
