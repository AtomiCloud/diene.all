import { commandSmoke } from './lib/flutter.ts';

export default commandSmoke(
  'flavor-builds',
  'Lapras, pichu, pikachu, and raichu build with their baked landscape define.',
  'nix develop .#default -c ./scripts/validate/flavor-builds.sh',
);
