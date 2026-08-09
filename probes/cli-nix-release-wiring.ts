import { staticGate } from './lib/cli-contract.ts';

export default staticGate('cli-nix-release-wiring', 'nix-release-wiring', {
  path: '.github/workflows/cd.yaml',
  find: 'nix build .#bun-cli',
  replace: 'nix build .#missing-cli',
});
