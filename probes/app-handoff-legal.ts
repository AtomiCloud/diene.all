import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<45s) — one SSR render slice. Ordering at FIRST PAINT is exactly what
// the requirement is about, and server rendering is the cheapest honest way to see
// it; the interactive progression through the flow is other rows' evidence.
const command =
  "nix develop .#ci -c bash -lc './scripts/ci/setup.sh && bun test --config=bunfig.int.toml tests/integration/app-handoff-legal.test.tsx'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-app-handoff-legal-green',
      description:
        'The legal/consent step is the first thing a signing-up user sees: no landscape is named and no choice is offered before consent.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'app-handoff-legal');
      },
    },
    {
      name: 'mutation-app-handoff-legal-caught',
      description: 'Showing the landscape list before consent turns the ordering slice red.',
      kind: 'mutation',
      expectedImpact: ['picker-journey'],
      async run(repo: any) {
        // Both screens still exist and the user still consents eventually, so a
        // manual walkthrough looks fine — the consent has simply stopped preceding
        // the thing it is consent for.
        const path = 'src/components/picker/PickerFlow.tsx';
        const source = await repo.read(path);
        await repo.write(path, source.replace('if (!consented) {', 'if (consented) {'));
        await expectBunRed(repo, command, 'app-handoff-legal');
      },
    },
  ],
};
