import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'build-time-landscape-policy',
  description: 'Landscape selection is compile-time only.',
  command: 'nix develop .#ci -c ./scripts/validate/landscape-policy.sh',
  file: 'lib/config/app_config.dart',
  find: 'static const String compiledLandscape = String.fromEnvironment(',
  replace: "static final String compiledLandscape = Platform.environment['LANDSCAPE'] ?? String.fromEnvironment(",
});
