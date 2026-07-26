import { runSitJourney } from './lib/consumer-sit.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-db-init-mode-sit-green',
      description: 'The compiled binary runs the one-shot postgres/kv/cache/storage db-init matrix.',
      kind: 'baseline',
      async run(repo: any) {
        await runSitJourney(repo, 'tests/sit/db-init-mode.sit.test.ts', 'db-init-mode-sit');
      },
    },
    {
      name: 'mutation-db-init-mode-sit-caught',
      description: 'Broken db-init dispatch turns the one-shot journey red.',
      kind: 'mutation',
      async run(repo: any) {
        const source = await repo.read('src/index.ts');
        const patched = source.replace("command('db-init')", "command('db-init-disabled')");
        if (patched === source) {
          throw new Error('no structural db-init command registration found in src/index.ts');
        }
        await repo.write('src/index.ts', patched);
        await runSitJourney(repo, 'tests/sit/db-init-mode.sit.test.ts', 'db-init-mode-sit', true);
      },
    },
  ],
};
