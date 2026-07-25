import { commandSmoke } from './lib/cli-contract.ts';

export default commandSmoke(
  'cli-version-stamped',
  'nix develop .#ci -c bash -lc \'./scripts/local/setup.sh && pls compile && test "$(dist/bin/bun-cli-linux-x64-baseline --version)" = "$(jq -r .version package.json)"\'',
);
