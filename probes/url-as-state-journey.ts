import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: heavy — a next build plus one Playwright slice. Deep-linkability is only
// observable through a real history stack, so the browser is the mechanism.
const command =
  'nix develop .#ci -c bash -lc \'./scripts/ci/setup.sh && export PATH="$(pwd)/node_modules/.bin:$PATH" && next build && ./scripts/local/standalone-assets.sh && playwright test url-as-state.spec.ts\'';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-url-as-state-journey-green',
      description:
        'Filter state lives in the URL: typing rewrites the query, the link reopens the same view, and back/forward restores it.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'url-as-state-journey');
      },
    },
    {
      name: 'mutation-url-as-state-journey-caught',
      description: 'A hook that keeps its state in React only, never writing the URL, turns the deep-link journey red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // Local-only state still renders correctly, so the regression is invisible
        // on screen: the URL simply stops describing the view and every shared
        // link opens the unfiltered page.
        const path = 'src/adapters/hooks/useUrlState.ts';
        const source = await repo.read(path);
        await repo.write(path, source.replace('return [state, controller.setState];', 'return [state, () => {}];'));
        await expectBunRed(repo, command, 'url-as-state-journey');
      },
    },
  ],
};
