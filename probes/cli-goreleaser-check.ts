import { commandGate } from './lib/cli-contract.ts';

export default commandGate('cli-goreleaser-check', 'nix develop .#releaser -c goreleaser check', {
  path: '.goreleaser.yaml',
  find: 'version: 2',
  replace: 'version: broken',
});
