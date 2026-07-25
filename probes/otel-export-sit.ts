import { runSitJourney } from './lib/consumer-sit.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-otel-export-sit-green',
      description: 'Logs, traces, and metrics traverse the local alloy → ClickHouse/VictoriaMetrics path in SIT.',
      kind: 'baseline',
      async run(repo: any) {
        await runSitJourney(repo, 'tests/sit/otel-export.sit.test.ts', 'otel-export-sit');
      },
    },
    {
      name: 'mutation-otel-export-sit-caught',
      description:
        'Broken exporter configuration turns the otel-export journey red while the app itself stays healthy.',
      kind: 'mutation',
      async run(repo: any) {
        const source = await repo.read('config/dev.yaml');
        const patched = source.replace(
          'otel:\n  endpoint: http://localhost:4318',
          'otel:\n  endpoint: http://localhost:14318',
        );
        if (patched === source) {
          throw new Error('no structural exporter endpoint found in config/dev.yaml');
        }
        await repo.write('config/dev.yaml', patched);
        await runSitJourney(repo, 'tests/sit/otel-export.sit.test.ts', 'otel-export-sit', true);
      },
    },
  ],
};
