import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<30s).
const command =
  "nix develop .#ci -c bash -lc './scripts/ci/setup.sh && bun test --config=bunfig.unit.toml tests/unit/content-flow.test.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-content-state-machine-green',
      description:
        'The content flow reaches exactly one terminal L/E/E state and an empty payload never reaches the content branch.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'content-state-machine');
      },
    },
    {
      name: 'mutation-content-state-machine-caught',
      description: 'Dropping the flow emptiness re-check turns the state-machine suite red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // Without the re-check an empty payload renders as content: the user sees
        // a blank panel instead of the empty state, which is the L/E/E defect
        // this gate exists to catch.
        const path = 'src/lib/content-flow/index.ts';
        const source = await repo.read(path);
        await repo.write(
          path,
          source.replace(
            'export const isEmptyFlowResult = (value: unknown): boolean => isEmptyContent(value);',
            'export const isEmptyFlowResult = (_value: unknown): boolean => false;',
          ),
        );
        await expectBunRed(repo, command, 'content-state-machine');
      },
    },
  ],
};
