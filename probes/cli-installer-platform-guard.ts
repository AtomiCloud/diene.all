import { commandGate } from './lib/cli-contract.ts';

export default commandGate(
  'cli-installer-platform-guard',
  "nix develop .#ci -c bash -lc './scripts/local/setup.sh && bun test tests/unit/install-contract.test.ts --test-name-pattern unsupported'",
  {
    path: 'scripts/release/install.sh',
    find: '  echo "❌ unsupported OS: ${os}" >&2\n  exit 1',
    replace: '  echo "❌ unsupported OS: ${os}" >&2\n  exit 0',
  },
);
