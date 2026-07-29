import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

const GATE = 'nix develop .#ci -c pls config:schema:verify';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-api-config-schema-green',
    description: 'The committed configuration schema matches the registered option blocks.',
    async run(repo: any) {
      await expectGreen(repo, GATE, 'dotnet-api-config-schema', 600000);
    },
  },
  mutation: {
    name: 'mutation-dotnet-api-config-schema-caught',
    description: 'Dropping a block from the generated schema turns the gen-check red.',
    async run(repo: any) {
      // Structural target: remove whichever block the registry declares FIRST, rather than
      // naming `otel` and breaking when the composed block set changes.
      const path = 'App/Config/settings.schema.json';
      const schema = JSON.parse(await repo.read(path));
      const blocks = Object.keys(schema.properties ?? {}).filter(key => !key.startsWith('$'));
      if (blocks.length === 0) throw new Error(`${path} declares no configuration blocks to drift`);

      delete schema.properties[blocks[0]];
      await repo.write(path, `${JSON.stringify(schema, null, 2)}\n`);

      await expectRed(repo, GATE, 'dotnet-api-config-schema', 600000);
    },
  },
});
