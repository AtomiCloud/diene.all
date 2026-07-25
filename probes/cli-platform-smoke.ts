import { commandSmoke } from './lib/cli-contract.ts';

export default commandSmoke(
  'cli-platform-smoke',
  "nix develop .#ci -c bash -lc './scripts/local/setup.sh && pls compile && ./scripts/release/smoke.sh dist/bin/bun-cli-linux-x64-baseline'",
);
