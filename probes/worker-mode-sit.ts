import { runSitJourney } from './lib/consumer-sit.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-worker-mode-sit-green',
      description: 'The compiled binary runs the worker journey against the local Garden emulation stack.',
      kind: 'baseline',
      async run(repo: any) {
        await runSitJourney(repo, 'tests/sit/worker-mode.sit.test.ts', 'worker-mode-sit');
      },
    },
    {
      name: 'mutation-worker-mode-sit-caught',
      description: 'Broken worker-mode dispatch turns the worker journey red.',
      kind: 'mutation',
      async run(repo: any) {
        const source = await repo.read('src/index.ts');
        const patched = source.replace("command('worker')", "command('worker-disabled')");
        if (patched === source) {
          throw new Error('no structural worker command registration found in src/index.ts');
        }
        await repo.write('src/index.ts', patched);
        await runSitJourney(repo, 'tests/sit/worker-mode.sit.test.ts', 'worker-mode-sit', true);
      },
    },
  ],
};
