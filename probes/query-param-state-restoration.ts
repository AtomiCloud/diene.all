import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'query-param-state-restoration',
  description: 'A shared link reproduces the whole filter state, field for field.',
  command: 'nix develop .#ci -c flutter test test/routing_query_state_test.dart',
  file: 'lib/routing/query_state.dart',
  // Omit one filter from the encoded state. Every field is asserted
  // individually, and `encodedFields` pins the full set, so a single dropped
  // key is caught rather than averaged away.
  find: "if (page != 1) _keyPage: '$page',",
  replace: '',
});
