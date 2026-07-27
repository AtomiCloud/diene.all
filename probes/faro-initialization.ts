import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'faro-initialization',
  description: 'Faro init fires at the collector with the exact LPSM attribute map.',
  command: 'nix develop .#ci -c flutter test test/observability_faro_test.dart',
  file: 'lib/observability/faro.dart',
  // Mis-deriving ONE app-meta key is the cheapest real sabotage: init still
  // fires, so only the exact-attribute-map assertion catches it.
  find: 'FaroAttributeKeys.appVersion: labels.version,',
  replace: 'FaroAttributeKeys.appVersion: labels.landscape,',
});
