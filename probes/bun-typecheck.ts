import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

const command = "nix develop .#ci -c bash -lc './scripts/local/setup.sh && pre-commit run typecheck --all-files'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-bun-typecheck-green',
      description: 'The generated typecheck hook accepts the strict TypeScript source.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'bun-typecheck');
      },
    },
    {
      name: 'mutation-bun-typecheck-caught',
      description: 'A TypeScript assignment error turns the typecheck hook red.',
      kind: 'mutation',
      // DELIBERATE DIVERGENCE FROM THE PARENT - do not "restore" byte-identity.
      // This probe is byte-identical to bun-base upstream, so ownership-by-bytes would
      // put this declaration there. It CANNOT live there: the control it names does not
      // exist on bun-base, and declaring it would be a dangling reference inherited by
      // every descendant. Ruled by noel 2026-07-29 to declare on the leaf and record the
      // divergence. expectedImpact names FEATURES, features are PER-TEMPLATE, so a static
      // list in a shared file cannot be correct on all surfaces - the file was never truly
      // shared, only coincidentally identical. Upstream fix filed: sulfone.lite #23 /
      // PROBES.md Gap 6 (absent feature should resolve INAPPLICABLE, not dangling).
      // MEASURED: control output was 'Failed to compile.' - it ran and failed.
      expectedImpact: ['bruno-collection'],
      async run(repo: any) {
        const path = (await repo.glob('src/lib/**/*.ts')).sort()[0];
        if (!path) throw new Error('no TypeScript library source found');
        await repo.write(path, `${await repo.read(path)}\nconst probeTypeError: string = 1;\nvoid probeTypeError;\n`);
        await expectBunRed(repo, command, 'bun-typecheck');
      },
    },
  ],
};
