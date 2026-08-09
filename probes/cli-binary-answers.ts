import { commandSmoke } from './lib/cli-contract.ts';

export default commandSmoke(
  'cli-binary-answers',
  "nix develop .#ci -c bash -lc './scripts/local/setup.sh && task test:sit'",
);
