import { commandSmoke } from './lib/cli-contract.ts';

export default commandSmoke(
  'cli-container-execution',
  "nix develop .#cd -c bash -lc 'docker build -f infra/Dockerfile -t bun-cli:probe . && docker run --rm bun-cli:probe --help'",
);
