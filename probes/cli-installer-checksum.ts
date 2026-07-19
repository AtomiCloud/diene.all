import { commandGate } from './lib/cli-contract.ts';

export default commandGate(
  'cli-installer-checksum',
  "nix develop .#ci -c bash -lc './scripts/local/setup.sh && bun test tests/unit/install-contract.test.ts --test-name-pattern checksum'",
  {
    path: 'scripts/release/install.sh',
    find: '    printf \'%s  %s\\n\' "${expected}" "${archive}" | sha256sum -c -',
    replace: '    true',
  },
);
