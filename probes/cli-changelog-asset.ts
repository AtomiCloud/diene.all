import { staticGate } from './lib/cli-contract.ts';

export default staticGate('cli-changelog-asset', 'changelog-asset', {
  path: 'atomi_release.yaml',
  find: '        - Changelog.old.md',
  replace: '        - Changelog.md',
});
