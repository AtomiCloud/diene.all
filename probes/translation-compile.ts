import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'translation-compile',
  description: 'Every shipped locale exposes the required typed keys.',
  command: 'nix develop .#ci -c ./scripts/validate/translations-compile.sh',
  file: 'lib/i18n/es.i18n.json',
  find: '"retryAction": "Intentar de nuevo"',
  replace: '"retryActionBroken": "Intentar de nuevo"',
});
