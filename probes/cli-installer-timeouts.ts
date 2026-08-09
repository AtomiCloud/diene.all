import { staticGate } from './lib/cli-contract.ts';

export default staticGate('cli-installer-timeouts', 'installer-timeouts', {
  path: 'scripts/release/install.sh',
  find: 'curl -fsSL --connect-timeout 30 --max-time 600 "${base}/${archive}"',
  replace: 'curl -fsSL "${base}/${archive}"',
});
