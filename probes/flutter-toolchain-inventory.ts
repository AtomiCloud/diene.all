import { commandSmoke } from './lib/flutter.ts';

export default commandSmoke(
  'flutter-toolchain-inventory',
  'The Flutter shell and every declared mobile binary perform a real operation.',
  'nix develop .#default -c ./scripts/validate/flutter-toolchain.sh',
);
