import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: heavy — builds the standalone server and runs the Bruno collection against
// it. `scripts/ci/bruno.sh` is the standalone slice of the e2e job (e2e.sh calls the
// same script), so the API contract can be exercised — and sabotaged — on its own.
const command = "nix develop .#ci -c bash -lc './scripts/ci/setup.sh && ./scripts/ci/bruno.sh'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-bruno-collection-green',
      description:
        'Every API route answers its Bruno assertions against the real standalone server: manifest, well-known documents, error-info, and the reminders surface.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'bruno-collection');
      },
    },
    {
      name: 'mutation-bruno-collection-caught',
      description: 'A manifest route that omits start_url turns the Bruno collection red.',
      kind: 'mutation',
      expectedImpact: ['pwa-manifest'],
      async run(repo: any) {
        // The ROUTE is sabotaged rather than an assertion: a corrupted test going red
        // proves nothing. Without start_url the manifest is still valid JSON and the
        // site still works — the app just stops being installable.
        const path = 'src/app/api/manifest/route.ts';
        const source = await repo.read(path);
        await repo.write(path, source.replace(/^\s*start_url: '\/',\n/m, ''));
        await expectBunRed(repo, command, 'bruno-collection');
      },
    },
  ],
};
