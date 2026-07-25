import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-config-schema-gen-check-green',
      description: 'The committed generated schema matches the zod root registry.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          "nix develop .#ci -c bash -lc './scripts/local/setup.sh && ./scripts/validate/schema-drift.sh'",
          'config-schema-gen-check',
        );
      },
    },
    {
      name: 'mutation-config-schema-gen-check-caught',
      description: 'A drifted committed schema turns the gen-check red.',
      kind: 'mutation',
      async run(repo: any) {
        const source = await repo.read('schemas/bun-consumer.schema.json');
        const drifted = source.replace('"type"', '"drifted-type"');
        if (drifted === source) {
          throw new Error('no structural drift target found in the generated schema');
        }
        await repo.write('schemas/bun-consumer.schema.json', drifted);
        await expectRed(
          repo,
          "nix develop .#ci -c bash -lc './scripts/local/setup.sh && ./scripts/validate/schema-drift.sh'",
          'config-schema-gen-check',
        );
      },
    },
  ],
};
