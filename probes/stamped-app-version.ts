import { commandSmoke } from './lib/flutter.ts';

export default commandSmoke(
  'stamped-app-version',
  'An emitted release APK reports the version stamped into pubspec.yaml.',
  'nix develop .#default -c ./scripts/validate/app-version-artifact.sh',
);
