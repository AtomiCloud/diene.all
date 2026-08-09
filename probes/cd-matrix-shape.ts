import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'cd-matrix-shape',
  description: 'CD emits four landscapes and a valid manual single-flavor filter.',
  command: 'nix develop .#ci -c ./scripts/validate/cd-matrix.sh',
  file: 'scripts/ci/cd-matrix.sh',
  find: "'{include: $include}'",
  replace: "'{items: $include}'",
});
