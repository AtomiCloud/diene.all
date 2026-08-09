import { staticGate } from './lib/cli-contract.ts';

export default staticGate('cli-fury-wiring', 'fury-wiring', {
  path: 'scripts/release/publish.sh',
  find: './scripts/release/fury.sh',
  replace: './scripts/release/missing-fury.sh',
});
