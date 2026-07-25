import { staticGate } from './lib/cli-contract.ts';

export default staticGate('cli-nfpms-formats', 'nfpms', {
  path: '.goreleaser.yaml',
  find: '    formats: [deb, rpm]',
  replace: '    formats: [deb]',
});
