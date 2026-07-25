import { expectGreen, expectRed } from './lib/helpers.ts';
import { breakAdapter } from './lib/go.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-integration-tests-green',
      description: 'Adapter tests pass against a real testcontainers dependency.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c ./scripts/local/test.sh int false false', 'integration-tests');
      },
    },
    {
      name: 'mutation-integration-tests-caught',
      description: 'Breaking an adapter write must turn the integration tier red.',
      kind: 'mutation',
      async run(repo: any) {
        await breakAdapter(repo);
        await expectRed(repo, 'nix develop .#ci -c ./scripts/local/test.sh int false false', 'integration-tests');
      },
    },
  ],
};
