import { expectGreen, expectRed } from './lib/helpers.ts';

// Gate: the C0 conformance harness (`dart test test/conformance`) recomputes
// the frozen Problem-envelope projection digest and compares it with SHA256SUMS.
// Sabotage corrupts that digest and proves the harness detects the drift.
const MEMBER = 'packages/diene_interfaces';
const CONFORMANCE =
  "nix develop .#ci --no-write-lock-file -c bash -lc 'cd packages/diene_interfaces && dart test test/conformance'";
const CHECKSUM = `${MEMBER}/test/fixtures/c0/SHA256SUMS`;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: [
      'nix develop .#ci --no-write-lock-file -c dart pub get --offline || nix develop .#ci --no-write-lock-file -c dart pub get',
    ],
  },
  probes: [
    {
      name: 'baseline-c0-fixture-harness-green',
      description: 'dart test test/conformance passes with the frozen projection checksum',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, CONFORMANCE, 'c0-fixture-harness');
      },
    },
    {
      name: 'mutation-c0-fixture-harness-caught',
      description: 'the conformance harness fails once a fixture digest is corrupted',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const ledger = await repo.read(CHECKSUM);
        const digest = ledger.match(/^[0-9a-f]{64}/)?.[0];
        if (!digest) {
          throw new Error('c0-fixture-harness: SHA256SUMS has no fixture digest');
        }
        const corrupted = (digest[0] === '0' ? '1' : '0') + digest.slice(1);
        await repo.write(CHECKSUM, ledger.replace(digest, corrupted));
        await expectRed(repo, CONFORMANCE, 'c0-fixture-harness');
      },
    },
  ],
};
