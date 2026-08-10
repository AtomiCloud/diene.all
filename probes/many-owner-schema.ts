import { expectGreen, expectRedBecause } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-many-owner-schema-green',
      description: 'Many-owner files have unique keyed blocks and required provenance.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c ./scripts/validate/many-owner.sh', 'many-owner-schema');
      },
    },
    {
      name: 'mutation-many-owner-schema-caught',
      description: 'A focused sabotage must turn the many-owner-schema mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const source = await repo.read('.gitignore');
        await repo.write('.gitignore', `${source}\n### workspace\n#### source: workspace\n`);
        await expectRedBecause(repo, 'nix develop .#ci -c ./scripts/validate/many-owner.sh', 'many-owner-schema', [
          "many-owner target '.gitignore' repeats owner key 'workspace'",
        ]);
      },
    },
  ],
};
