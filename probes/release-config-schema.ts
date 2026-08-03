import { expectGreen, expectRedBecause } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-release-config-schema-green',
      description: 'The release configuration parses and satisfies the workspace schema.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#ci -c ./scripts/validate/release-config.sh schema',
          'release-config-schema',
        );
      },
    },
    {
      name: 'mutation-release-config-schema-caught',
      description: 'A focused sabotage must turn the release-config-schema mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const path = 'atomi_release.yaml';
        const source = await repo.read(path);

        // Structural anchor, indentation-agnostic: the `branches:` key at any indent, followed by its
        // first sequence item `- main` at a strictly deeper indent (\1 plus at least one more space).
        // Fires identically on schemaVersion 1 (top-level `branches:`) and schemaVersion 2
        // (`release.branches`), so one expression addresses both lineages.
        const target = /^([ \t]*)branches:[ \t]*\n(\1[ \t]+)- main[ \t]*$/gm;

        // Load-bearing: zero or several targets must fail the probe loudly (author error -> `missed`)
        // rather than silently mutate nothing or every `branches:` key at once.
        const hits = [...source.matchAll(target)];
        if (hits.length !== 1) {
          throw new Error(
            `${path} must contain exactly one \`branches:\` block whose first entry is \`- main\`; found ${hits.length}`,
          );
        }

        const mutated = source.replace(
          target,
          (_match: string, keyIndent: string, itemIndent: string) => `${keyIndent}branches:\n${itemIndent}- develop`,
        );
        await repo.write(path, mutated);

        await expectRedBecause(
          repo,
          'nix develop .#ci -c ./scripts/validate/release-config.sh schema',
          'release-config-schema',
          ['canonical releaser configuration is invalid'],
        );
      },
    },
  ],
};
