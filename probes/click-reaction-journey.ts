import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<30s) — the re-entrancy decision is a pure state machine.
const command =
  "nix develop .#ci -c bash -lc './scripts/ci/setup.sh && bun test --config=bunfig.unit.toml tests/unit/async-action.test.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-click-reaction-journey-green',
      description:
        'An async trigger admits exactly one in-flight run and returns to idle whether it resolves or rejects.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'click-reaction-journey');
      },
    },
    {
      name: 'mutation-click-reaction-journey-caught',
      description: 'Admitting a second run while one is in flight turns the re-entrancy suite red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // The button still shows pending state, so the regression is invisible:
        // a double click simply submits twice.
        const path = 'src/lib/async-action/index.ts';
        const source = await repo.read(path);
        await repo.write(
          path,
          source.replace(
            'isPending(state) ? { admitted: false, state } : { admitted: true, state: { pending: true } };',
            '{ admitted: true, state: { pending: true } };',
          ),
        );
        await expectBunRed(repo, command, 'click-reaction-journey');
      },
    },
  ],
};
