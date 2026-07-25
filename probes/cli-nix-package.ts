import { commandSmoke } from './lib/cli-contract.ts';

export default commandSmoke('cli-nix-package', 'nix build .#bun-cli && ./result/bin/bun-cli --help');
