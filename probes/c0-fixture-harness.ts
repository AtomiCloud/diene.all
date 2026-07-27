import { expectGreen, expectRed } from './lib/helpers.ts';

// Gate: the C0 conformance harness (`flutter test test/conformance`) recomputes
// fixture digests and compares them against the checked-in manifest. Sabotage
// corrupts the first fixture digest and proves the harness detects the drift.
export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: [
      'nix develop .#ci --no-write-lock-file -c flutter pub get --offline || nix develop .#ci --no-write-lock-file -c flutter pub get',
    ],
  },
  probes: [
    {
      name: 'baseline-c0-fixture-harness-green',
      description: 'flutter test test/conformance passes with the pristine fixture manifest',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          "nix develop .#ci --no-write-lock-file -c bash -lc 'cd packages/diene_e2e && flutter test test/conformance'",
          'c0-fixture-harness',
        );
      },
    },
    {
      name: 'mutation-c0-fixture-harness-caught',
      description: 'the conformance harness fails once a fixture digest is corrupted',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const manifests = (await repo.glob('packages/*/test/fixtures/c0/manifest.json')).sort();
        const target = manifests[0];
        if (!target) {
          throw new Error('c0-fixture-harness: no fixture manifest to sabotage');
        }
        const manifest = JSON.parse(await repo.read(target));
        const entries = manifest.fixtures ?? {};
        const firstKey = Object.keys(entries)[0];
        if (!firstKey) {
          throw new Error('c0-fixture-harness: fixture manifest has no entries');
        }
        const digest = String(entries[firstKey]);
        entries[firstKey] = (digest[0] === '0' ? '1' : '0') + digest.slice(1);
        await repo.write(target, `${JSON.stringify(manifest, null, 2)}\n`);
        await expectRed(
          repo,
          "nix develop .#ci --no-write-lock-file -c bash -lc 'cd packages/diene_e2e && flutter test test/conformance'",
          'c0-fixture-harness',
        );
      },
    },
  ],
};
