import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'release-pubspec-stamp',
  description: 'Release preparation stamps VERSION and pubspec.yaml together.',
  command: 'nix develop .#ci -c ./scripts/validate/release-pubspec.sh',
  file: 'scripts/release/bump.sh',
  find: 'sed -i -E "s/^version: .*/version: ${version#v}+${build_number}/" pubspec.yaml',
  replace: 'true # pubspec stamp removed',
});
