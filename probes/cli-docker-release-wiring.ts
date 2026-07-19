import { staticGate } from './lib/cli-contract.ts';

export default staticGate('cli-docker-release-wiring', 'docker-release', {
  path: '.github/workflows/cd.yaml',
  find: 'uses: ./.github/workflows/⚡reusable-docker.yaml',
  replace: 'uses: ./.github/workflows/⚡reusable-missing.yaml',
});
