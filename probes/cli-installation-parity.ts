import { staticGate } from './lib/cli-contract.ts';

export default staticGate('cli-installation-parity', 'installation-parity', {
  path: 'INSTALLATION.md',
  find: 'bun-cli_<os>_<arch>.tar.gz',
  replace: 'bun-cli_<os>_<arch>_missing.tar.gz',
});
