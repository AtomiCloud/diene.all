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
        'Broken exporter configuration turns the otel-export journey red while the app itself stays healthy.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // ONE fault: point the OTLP exporter endpoints at an address that accepts no
        // OTLP, so telemetry never reaches the backends while the worker keeps
        // running and its dependency-blind health probe stays green — that asymmetry
        // is precisely the regression this row exists for (a broken exporter must NOT
        // be masked by a healthy k8s probe). The target is the landscape overlay's
        // exporter endpoints, matched by PATTERN under the otel block rather than by
        // a named sample file, and the address is a reserved-for-documentation host
        // (RFC 5737 TEST-NET-1) rather than a hardcoded loopback literal.
        const paths = (await repo.glob('config/*.settings.yaml')).sort();
        for (const path of paths) {
          const source = await repo.read(path);
          if (!/^otel:$/m.test(source) || !/^\s+endpoint:\s*\S+\s*$/m.test(source)) {
            continue;
          }
          const patched = source.replace(/^(\s+)endpoint:\s*\S+\s*$/gm, '$1endpoint: http://192.0.2.1:4318');
          if (patched === source) {
            continue;
          }
          await repo.write(path, patched);
          await runSitJourney(repo, JOURNEY, 'otel-export-sit', true);
          return;
        }
        throw new Error('no structural otel exporter endpoint found in a landscape overlay');
      },
    },
  ],
};
