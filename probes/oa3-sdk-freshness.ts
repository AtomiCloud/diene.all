import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'oa3-sdk-freshness',
  description: 'The generated OA3 SDK matches its source schema.',
  command: 'nix develop .#ci -c ./scripts/validate/generated.sh sdk',
  file: 'openapi/service.openapi.yaml',
  find: 'homeLandscape:',
  replace: 'homeRegion:',
});
