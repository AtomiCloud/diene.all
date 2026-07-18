import { expectGreen, expectRed } from './lib/helpers.ts';
import { plantProductionOnlySymbol } from './lib/go.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-deadcode-production-green',
      description: 'Production-only deadcode and staticcheck pass without test reachability.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c ./scripts/local/deadcode.sh production', 'deadcode-production');
      },
    },
    {
      name: 'mutation-deadcode-production-caught',
      description: 'A symbol reachable only from a test must turn the production pass red.',
      kind: 'mutation',
      async run(repo: any) {
        await plantProductionOnlySymbol(repo);
        await expectRed(repo, 'nix develop .#ci -c ./scripts/local/deadcode.sh production', 'deadcode-production');
      },
    },
  ],
};
