// COST CLASS: heavy, SERIALIZED (see probes/lib/consumer-sit.ts).
//
// Why heavy is unavoidable: G1 forbids a fake collector for this mechanism. Logs,
// traces, and metrics must traverse the REAL telemetry path — the app's OTLP
// http/protobuf exporter on :4318 → alloy → ClickHouse / VictoriaMetrics — and be
// read back out of those backends. A mocked exporter proves the SDK call, not the
// wire, and the int tier already covers the mocked case.
import { runSitJourney } from './lib/consumer-sit.ts';

const JOURNEY = 'TestOtelExportJourney';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-otel-export-sit-green',
      description: 'Logs, traces, and metrics traverse the real alloy → ClickHouse/VictoriaMetrics path in SIT.',
      kind: 'baseline',
      async run(repo: any) {
        await runSitJourney(repo, JOURNEY, 'otel-export-sit');
      },
    },
    {
      name: 'mutation-otel-export-sit-caught',
      description:
        'Pointing the exporter endpoint the SIT actually honours at an address that accepts no OTLP turns the otel-export journey red — telemetry never reaches the backends — while the app itself stays healthy.',
      kind: 'mutation',
      // Same-template collateral (R-E18), empirically observed live — and NOT the "app
      // stays healthy" this row's prose assumes. EVERY command (worker AND db-init) builds
      // the telemetry runtime, and `runtime.Close` flushes the OTLP exporter to the
      // black-holed endpoint, blocking ~65s and then erroring, so the command exits
      // non-zero. Every one of the four sibling rows therefore reddens. Because
      // expectedImpact declares away EVERY co-selected control, NO clean control survives
      // and this row's `caught` is only HALF-PROVEN (read-verdict.ts flags it). The durable
      // disposition is a non-fatal exporter shutdown and/or an R-E7 partition; not my scope.
      expectedImpact: ['worker-mode-sit', 'db-init-mode-sit', 'db-init-idempotency-sit', 'message-journey-sit'],
      async run(repo: any) {
        // ONE fault: point the OTLP exporter endpoint the SIT ACTUALLY USES at an
        // address that accepts no OTLP, so telemetry never reaches the backends while
        // the worker keeps running and its dependency-blind health probe stays green —
        // that asymmetry is precisely the regression this row exists for.
        //
        // The load-bearing endpoint is NOT the landscape overlay (config/*.settings.yaml).
        // scripts/local/test-sit.sh reads config/dev.yaml, and scripts/local/with-dev-env.sh
        // exports ATOMI_OTEL__{LOGS,METRICS,TRACES}__EXPORTER__OTLP__ENDPOINT from its
        // `.otel.endpoint` — and an ATOMI_ env var OVERRIDES the overlay, so patching the
        // overlay is a SUCCESSFUL NO-OP (the original miss on this row). The one endpoint
        // whose change the worker honours in SIT is config/dev.yaml `.otel.endpoint`.
        // Target ONLY the otel block: the clickhouse/victoriaMetrics endpoints in the same
        // file feed the journey's own read-back queries, and clobbering them would fail the
        // journey for the WRONG reason. The address is a reserved-for-documentation host
        // (RFC 5737 TEST-NET-1). The patch MUST change the file or it is refused — a
        // no-op sabotage reads as a gate hole rather than as the broken probe it is.
        const devConfig = 'config/dev.yaml';
        const source = await repo.read(devConfig);
        const otelEndpoint = source.match(/(^otel:\n[ \t]+endpoint:[ \t]*)\S+[ \t]*$/m);
        if (!otelEndpoint) {
          throw new Error('no structural otel endpoint found in the SIT dev config config/dev.yaml');
        }
        const patched = source.replace(otelEndpoint[0], `${otelEndpoint[1]}http://192.0.2.1:4318`);
        if (patched === source) {
          throw new Error('otel endpoint sabotage did not change config/dev.yaml; refusing to run a no-op mutation');
        }
        await repo.write(devConfig, patched);
        await runSitJourney(repo, JOURNEY, 'otel-export-sit', true);
      },
    },
  ],
};
