import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-schema-drift-green',
    description: 'The checked-in values schema matches the annotated values source.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh schema-drift',
        'wrapper-schema-drift',
      );
    },
  },
  mutation: {
    name: 'mutation-wrapper-schema-drift-caught',
    description: 'Changing a schema annotation without regeneration is detected.',
    expectedImpact: [],
    async run(repo: any) {
      const path = 'chart/values.yaml';
      const original = await repo.read(path);
      try {
        await repo.patch(path, {
          find: 'provider: digitalocean # @schema enum:[aws, oci, digitalocean]',
          replace: 'provider: digitalocean # @schema enum:[oci, digitalocean]',
        });
        await expectRed(
          repo,
          'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh schema-drift',
          'wrapper-schema-drift',
        );
      } finally {
        await repo.write(path, original);
      }
    },
  },
});
