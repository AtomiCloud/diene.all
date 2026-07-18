import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'slang-freshness',
  description: 'Generated Slang output matches locale sources.',
  command: 'nix develop .#ci -c ./scripts/validate/generated.sh translations',
  file: 'lib/i18n/en.i18n.json',
  find: '"heroEyebrow": "MOBILE FOUNDATION"',
  replace: '"heroEyebrow": "MOBILE FOUNDATION CHANGED"',
});
