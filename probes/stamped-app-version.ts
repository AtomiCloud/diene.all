import { commandSmoke } from './lib/flutter.ts';

export default commandSmoke(
  'stamped-app-version',
  'The release helper reports the version stamped into pubspec.yaml.',
  'nix develop .#ci -c ./scripts/validate/release-pubspec.sh',
);
