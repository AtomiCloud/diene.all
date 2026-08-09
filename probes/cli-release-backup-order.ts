import { staticGate } from './lib/cli-contract.ts';

export default staticGate('cli-release-backup-order', 'release-backup-order', {
  path: 'release.yaml',
  find: '      - phase: beforeWrite',
  replace: '      - phase: afterWrite',
});
