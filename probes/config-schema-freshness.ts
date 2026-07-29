import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'config-schema-freshness',
  description: 'The generated config schema matches its authored generator.',
  command: 'nix develop .#ci -c ./scripts/validate/generated.sh config',
  file: 'tool/generate-config-schema.ts',
  find: "title: 'Diene Flutter Base Configuration',",
  replace: "title: 'Changed Configuration',",
});
