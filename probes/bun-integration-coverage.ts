import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

const command = 'nix develop .#ci -c ./scripts/ci/test.sh int';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-bun-integration-coverage-green',
      description: 'Integration runs real-server contracts without claiming a second production ledger.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'bun-integration-coverage');
        if ((await repo.glob('coverage/int/lcov.info')).length !== 0) {
          throw new Error('integration must not emit a duplicate production coverage ledger');
        }
      },
    },
    {
      name: 'mutation-bun-integration-coverage-caught',
      description: 'A broken real-server expectation turns the integration contract gate red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const path = 'tests/integration/http-contract.test.ts';
        const source = await repo.read(path);
        await repo.write(path, source.replace("source: 'real-server'", "source: 'mutated-server'"));
        await expectBunRed(repo, command, 'bun-integration-coverage');
      },
    },
  ],
};
