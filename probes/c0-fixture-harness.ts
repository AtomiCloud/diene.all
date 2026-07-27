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
          "nix develop .#ci --no-write-lock-file -c bash -lc 'cd packages/diene_auth_engine && flutter test test/conformance'",
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
        // The inherited sample sabotaged a `manifest.json` carrying a
        // `fixtures` digest MAP. This package uses a `SHA256SUMS` ledger
        // instead — the accepted diene_interfaces shape, and the one
        // `tool/gen_c0_projection.dart` writes. Sabotaging the file the harness
        // does not read would have made this mutation VACUOUSLY green: the
        // conformance suite would have stayed green and the row would still have
        // been recorded as "caught".
        const ledgers = (await repo.glob('packages/*/test/fixtures/c0/SHA256SUMS')).sort();
        const target = ledgers[0];
        if (!target) {
          throw new Error('c0-fixture-harness: no SHA256SUMS ledger to sabotage');
        }
        const ledger = await repo.read(target);
        const digest = ledger.match(/^[0-9a-f]{64}/m)?.[0];
        if (!digest) {
          throw new Error(
            `c0-fixture-harness: no sha256 digest found in ${target} — refusing ` +
              'to report a caught mutation without having changed anything',
          );
        }
        // Flip the first nibble so the recorded digest can no longer match the
        // fixture bytes.
        const corrupted = (digest[0] === '0' ? '1' : '0') + digest.slice(1);
        await repo.write(target, ledger.replace(digest, corrupted));
        await expectRed(
          repo,
          "nix develop .#ci --no-write-lock-file -c bash -lc 'cd packages/diene_auth_engine && flutter test test/conformance'",
          'c0-fixture-harness',
        );
      },
    },
  ],
};
