import { commandSmoke } from './lib/cli-contract.ts';

export default commandSmoke(
  'cli-installer-supported',
  'nix develop .#ci -c bash -lc \'./scripts/local/setup.sh && bun test tests/unit/install-contract.test.ts --test-name-pattern "complete the supported"\'',
);
