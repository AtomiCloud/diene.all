// COST CLASS: heavy, SERIALIZED (see probes/lib/consumer-sit.ts) — it brings the
// local dependency stack up and drives the compiled artifact.
//
// The mechanism is the health-check METRIC arriving in the metrics backend. It
// rides the same real telemetry path as otel-export-sit — that path is the only
// place the metric can be read back — but it is an independently asserted
// mechanism (S26) with its own row and its own failure. It carries no sabotage:
// the exporter fault belongs to otel-export-sit, which owns that mechanism.
//
// Proven-only smoke: no sabotage.
import { runSitJourney } from './lib/consumer-sit.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-health-metric-green',
      description: 'The expected OTEL health-check metric is observed in the local metrics backend.',
      kind: 'baseline',
      async run(repo: any) {
        await runSitJourney(repo, 'TestOtelExportJourney', 'health-metric');
      },
    },
  ],
};
