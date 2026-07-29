import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'flavor-tokenization',
  description: 'Flavor identities and the CD matrix derive from lpsm.yaml.',
  command: "nix develop .#ci -c bash -c './scripts/ci/lpsm-lint.sh && ./scripts/validate/cd-matrix.sh'",
  file: 'scripts/ci/cd-matrix.sh',
  find: 'domain="$(yq \'.domain\' "${lpsm}")"',
  replace: 'domain="cloud.fixed"',
});
