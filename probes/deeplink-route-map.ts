import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<30s).
const command =
  "nix develop .#ci -c bash -lc './scripts/ci/setup.sh && bun test --config=bunfig.unit.toml tests/unit/deeplink-route-map.test.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-deeplink-route-map-green',
      description:
        'Every deeplink route maps web to app and back over an identical parameter set, so either side can derive its half.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'deeplink-route-map');
      },
    },
    {
      name: 'mutation-deeplink-route-map-caught',
      description: 'An asymmetric route entry turns the route-map validation red.',
      kind: 'mutation',
      // MEASURED COLLATERAL (family: shared source read by the unit suite). This
      // sabotage edits a real src/ module, and bunfig.unit.toml roots the suite at
      // tests/unit where 16 of 20 files import ../../src/**, so the whole unit run
      // reddens. On the 6f5907a matrix this row broke with control_failed naming
      // diene/bun-base#bun-unit-tests, control output "task: [unit:default] bun test"
      // - the control RAN and FAILED, so the blame was correct, and the empty array
      // here was a positive assertion of no collateral that got believed.
      expectedImpact: ['bun-unit-tests'],
      async run(repo: any) {
        // A web pattern with no parameter against an app pattern that needs one is
        // a link the app cannot resolve — and it looks entirely reasonable in the
        // table until something checks both sides agree.
        const path = 'src/lib/deeplink/route-map.ts';
        const source = await repo.read(path);
        await repo.write(
          path,
          source.replace(
            "  { id: 'settings', web: '/settings', app: '/settings' },",
            "  { id: 'settings', web: '/settings', app: '/settings' },\n  { id: 'orphan', web: '/orphan', app: '/orphan/:id' },",
          ),
        );
        await expectBunRed(repo, command, 'deeplink-route-map');
      },
    },
  ],
};
