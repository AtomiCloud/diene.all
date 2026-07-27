import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'content-state-machine',
  description: 'Loading/empty/error/content transitions carry stale content exactly as the contract says.',
  command: 'nix develop .#ci -c flutter test test/content_state_test.dart',
  file: 'lib/content/content_state.dart',
  // Flip one transition: a refresh now blanks the screen instead of carrying
  // the stale content into the loading tier.
  find: 'ContentLoading<T>(previous: current.displayable);',
  replace: 'ContentLoading<T>();',
});
