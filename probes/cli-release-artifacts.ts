import { staticGate } from './lib/cli-contract.ts';

export default staticGate('cli-release-artifacts', 'release-artifacts', {
  path: '.goreleaser.yaml',
  find: '    - glob: scripts/release/install.sh',
  replace: '    - glob: scripts/release/missing.sh',
});
