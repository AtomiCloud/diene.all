import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<30s) — one bun script, no build.
const command = "nix develop .#ci -c bash -lc './scripts/ci/setup.sh && bun scripts/local/config-schema.ts --check'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-config-schema-gen-green',
      description: 'The committed config/schema.json matches the schema generated from the composed registry.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'config-schema-gen');
      },
    },
    {
      name: 'mutation-config-schema-gen-caught',
      description: 'A hand-edited property in config/schema.json turns the gen-check red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // A stale editor schema silently stops flagging invalid config, so drift
        // between the generated and committed schema must never pass.
        const path = 'config/schema.json';
        const schema = JSON.parse(await repo.read(path));
        schema['properties']['branding']['properties']['appName'] = { type: 'number' };
        await repo.write(path, `${JSON.stringify(schema, null, 2)}\n`);
        await expectBunRed(repo, command, 'config-schema-gen');
      },
    },
  ],
};
