import { runSitJourney } from './lib/consumer-sit.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-db-init-idempotency-sit-green',
      description: 'A second seed-if-not-exists run creates no duplicates.',
      kind: 'baseline',
      async run(repo: any) {
        await runSitJourney(repo, 'tests/sit/db-init-idempotency.sit.test.ts', 'db-init-idempotency-sit');
      },
    },
    {
      name: 'mutation-db-init-idempotency-sit-caught',
      description: 'Replacing the idempotent seed selection with an unconditional insert turns the re-run journey red.',
      kind: 'mutation',
      async run(repo: any) {
        const source = await repo.read('src/init/seeds.ts');
        const patched = source.replace(
          'selectMissingSeedRecords(records, existing)',
          'selectMissingSeedRecords(records, new Set([...existing].filter(id => !existing.has(id))))',
        );
        if (patched === source) {
          throw new Error('no structural seed-if-not-exists selection found in src/init/seeds.ts');
        }
        await repo.write('src/init/seeds.ts', patched);
        await runSitJourney(repo, 'tests/sit/db-init-idempotency.sit.test.ts', 'db-init-idempotency-sit', true);
      },
    },
  ],
};
