import { commandSmoke } from './lib/cli-contract.ts';

export default commandSmoke(
  'cli-compile',
  "nix develop .#ci -c bash -lc './scripts/local/setup.sh && pls compile && test -x dist/bin/bun-cli-linux-x64-baseline && test -x dist/bin/bun-cli-linux-arm64 && test -x dist/bin/bun-cli-darwin-arm64'",
);
