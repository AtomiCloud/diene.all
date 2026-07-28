import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'presence-codecov-config',
      description: 'Informational unit and integration flags exist with carryforward enabled.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          "nix develop .#ci -c yq -e '.flags.unit.carryforward == true and .flags.int.carryforward == true' .codecov.yaml",
          'codecov-config',
        );
      },
    },
    {
      name: 'mutation-codecov-config-caught',
      description: 'A well-formed carryforward sabotage must turn the Codecov predicate red.',
      kind: 'mutation',
      async run(repo: any) {
        const original = await repo.read('.codecov.yaml');
        await repo.patch('.codecov.yaml', { find: 'carryforward: true', replace: 'carryforward: false' });
        const sabotaged = await repo.read('.codecov.yaml');
        if (sabotaged === original || !sabotaged.includes('carryforward: false')) {
          throw new Error('codecov-config sabotage did not change .codecov.yaml');
        }
        await expectGreen(repo, "nix develop .#ci -c yq '.' .codecov.yaml", 'codecov-parse-guard');
        await expectRed(
          repo,
          "nix develop .#ci -c yq -e '.flags.unit.carryforward == true and .flags.int.carryforward == true' .codecov.yaml",
          'codecov-config-mutation',
        );
      },
    },
  ],
};
