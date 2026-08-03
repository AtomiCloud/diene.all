import { BUN_PROBE_SANDBOX, BUN_PROBE_SETUP } from './lib/bun.ts';
import { expectGreen, expectRedBecause } from './lib/helpers.ts';

const gate = 'nix develop --no-write-lock-file .#ci -c pre-commit run a-biome --all-files';

export default {
  contractVersion: 1,
  sandbox: BUN_PROBE_SANDBOX,
  setup: BUN_PROBE_SETUP,
  probes: [
    {
      name: 'baseline-bun-biome-lint-green',
      description: 'The Biome lint hook accepts the sample source and tests with the formatter left off.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'bun-biome-lint');
      },
    },
    {
      name: 'mutation-bun-biome-lint-caught',
      description: 'A loose equality must be refused as noDoubleEquals, not merely fail.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const paths = (await repo.glob('src/lib/**/*.ts')).sort();
        if (paths.length === 0) {
          throw new Error('no domain source file found to plant a lint violation in');
        }
        const path = paths[0];
        const source = await repo.read(path);
        // A top-level local, not an exported function: it runs on import so coverage stays whole,
        // and it exports nothing so Knip stays quiet. `Number(1)` keeps the operands same-typed.
        await repo.write(
          path,
          `${source.trimEnd()}\n\n// Probe sabotage: a loose equality Biome must refuse.\nconst probeBiomeViolation = Number(1) == 1;\nvoid probeBiomeViolation;\n`,
        );
        await expectRedBecause(repo, gate, 'bun-biome-lint', ['lint/suspicious/noDoubleEquals', path]);
      },
    },
  ],
};
