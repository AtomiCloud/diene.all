import { expectGreen } from './lib/helpers.ts';

// Smoke: the shipped example consumes the library's public API and runs cleanly,
// proving the package is usable by downstream consumers.
export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: [
      'nix develop .#ci --no-write-lock-file -c flutter pub get --offline || nix develop .#ci --no-write-lock-file -c flutter pub get',
    ],
  },
  probes: [
    {
      name: 'baseline-sample-execution-consumption-green',
      description: 'the shipped example runs successfully against the library API',
      kind: 'baseline',
      async run(repo: any) {
        const examples = (await repo.glob('packages/*/example/*.dart')).sort();
        const target = examples[0];
        if (!target) {
          throw new Error('sample-execution-consumption: no example entrypoint found');
        }
        const member = target.replace(/\/example\/[^/]+$/, '');
        const relative = target.slice(member.length + 1);
        await expectGreen(
          repo,
          `nix develop .#ci --no-write-lock-file -c bash -lc 'cd ${member} && flutter pub run ${relative}'`,
          'sample-execution-consumption',
        );
      },
    },
  ],
};
