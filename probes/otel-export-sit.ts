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
        const source = await repo.read('tests/sit/driver.ts');
        const patched = source.replace(
          'ATOMI_OTEL__TRACES__EXPORTER__OTLP__ENDPOINT: devConfig.otel.endpoint,',
          "ATOMI_OTEL__TRACES__EXPORTER__OTLP__ENDPOINT: 'https://localhost:4318',",
        );
        if (patched === source) {
          throw new Error('no structural trace exporter endpoint found in tests/sit/driver.ts');
        }
        await repo.write('tests/sit/driver.ts', patched);
        await runSitJourney(repo, 'tests/sit/otel-export.sit.test.ts', 'otel-export-sit', true);
      },
    },
  ],
};
