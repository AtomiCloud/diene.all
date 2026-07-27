import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: heavy — the draft contract at the unit tier PLUS the browser journey that
// proves the same policy survives a real refresh. The sabotage below reddens the
// contract half; the browser half is baseline-only evidence.
const contract =
  "nix develop .#ci -c bash -lc './scripts/ci/setup.sh && bun test --config=bunfig.unit.toml tests/unit/form-draft-contract.test.ts'";
const journey =
  'nix develop .#ci -c bash -lc \'./scripts/ci/setup.sh && export PATH="$(pwd)/node_modules/.bin:$PATH" && next build && ./scripts/local/standalone-assets.sh && playwright test form-lifecycle.spec.ts\'';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-form-lifecycle-journey-green',
      description:
        'A draft persists as the user types, survives a refresh, is offered back, and is cleared by each terminal trigger.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, contract, 'form-lifecycle-journey');
        await expectBunGreen(repo, journey, 'form-lifecycle-journey');
      },
    },
    {
      name: 'mutation-form-lifecycle-journey-caught',
      description: 'Offering a restore for a pristine draft turns the draft-policy suite red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // An always-true restore decision prompts "restore your draft?" on a form
        // the user never typed into, which reads as a bug in the app rather than
        // in the storage layer.
        const path = 'src/lib/form-draft/index.ts';
        const source = await repo.read(path);
        await repo.write(
          path,
          source.replace('if (draft === undefined) return false;', 'if (draft === undefined) return true;'),
        );
        await expectBunRed(repo, contract, 'form-lifecycle-journey');
      },
    },
  ],
};
