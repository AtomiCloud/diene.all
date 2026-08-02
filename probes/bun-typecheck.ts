import { BUN_PROBE_SANDBOX, BUN_PROBE_SETUP } from './lib/bun.ts';
import { expectGreen, expectRedBecause } from './lib/helpers.ts';

const gate = 'nix develop --no-write-lock-file .#ci -c pre-commit run a-typecheck --all-files';

export default {
  contractVersion: 1,
  sandbox: BUN_PROBE_SANDBOX,
  setup: BUN_PROBE_SETUP,
  probes: [
    {
      name: 'baseline-bun-typecheck-green',
      description: 'The strict TypeScript typecheck hook accepts the sample source and tests.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'bun-typecheck');
      },
    },
    {
      name: 'mutation-bun-typecheck-caught',
      description: 'A wrong return type must be refused as TS2322, not merely fail.',
      kind: 'mutation',
      expectedImpact: ['bun-knip-repository'],
      async run(repo: any) {
        const paths = (await repo.glob('src/lib/**/*.ts')).sort();
        if (paths.length === 0) {
          throw new Error('no domain source file found to break the type of');
        }
        const path = paths[0];
        const source = await repo.read(path);
        await repo.write(
          path,
          `${source.trimEnd()}\n\nexport function probeTypeError(seed: string): number {\n  return seed;\n}\n`,
        );
        await expectRedBecause(repo, gate, 'bun-typecheck', ['error TS2322', path]);
      },
    },
  ],
};
