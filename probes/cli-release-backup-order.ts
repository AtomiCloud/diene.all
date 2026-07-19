import { staticGate } from './lib/cli-contract.ts';

export default staticGate('cli-release-backup-order', 'release-backup-order', {
  path: 'atomi_release.yaml',
  find: '      prepareCmd: ./scripts/release/backup-changelog.sh',
  replace: '      prepareCmd: ./scripts/release/bump.sh 0.0.0',
});
