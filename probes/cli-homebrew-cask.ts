import { staticGate } from './lib/cli-contract.ts';

export default staticGate('cli-homebrew-cask', 'homebrew-cask', {
  path: '.goreleaser.yaml',
  find: 'com.apple.quarantine',
  replace: 'com.apple.not-quarantine',
});
