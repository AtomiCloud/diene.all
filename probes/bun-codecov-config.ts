import { expectBunGreen } from './lib/bun-command.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'presence-bun-codecov-config',
      description: 'Codecov configuration parses with informational unit and int carryforward flags.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(
          repo,
          "nix develop .#ci -c yq -e '.flags.unit.carryforward == true and .flags.int.carryforward == true and .coverage.status.project.default.informational == true and .coverage.status.patch.default.informational == true' codecov.yml",
          'bun-codecov-config',
        );
      },
    },
  ],
};
