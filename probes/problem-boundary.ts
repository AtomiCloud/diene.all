import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<30s).
const command =
  "nix develop .#ci -c bash -lc './scripts/ci/setup.sh && bun test --config=bunfig.unit.toml tests/unit/problem-boundary.test.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-problem-boundary-green',
      description:
        'A thrown Error wraps into a LocalError Problem with message and stack, and both error boundaries render through the Problem view.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'problem-boundary');
      },
    },
    {
      name: 'mutation-problem-boundary-caught',
      description: 'A route boundary that renders the raw error instead of wrapping it turns the boundary suite red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // Rendering `error.message` directly puts a raw exception (and whatever
        // it leaked into its message) on the user's screen — the exact defect the
        // Problem boundary exists to prevent.
        const path = 'src/app/[locale]/error.tsx';
        const source = await repo.read(path);
        await repo.write(
          path,
          source
            .replace('const problem = toProblem(error);', '')
            .replace('{defaultProblemView(problem)}', '<pre>{error.message}</pre>'),
        );
        await expectBunRed(repo, command, 'problem-boundary');
      },
    },
  ],
};
