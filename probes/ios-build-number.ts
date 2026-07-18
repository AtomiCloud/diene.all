import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'ios-build-number',
  description: 'The iOS build-number guard implements max(store+1, run).',
  command: 'nix develop .#ci -c ./scripts/validate/build-numbers.sh',
  file: 'scripts/ci/lib-ios.sh',
  find: 'next="$((latest + 1))"',
  replace: 'next="$((latest + 2))"',
});
