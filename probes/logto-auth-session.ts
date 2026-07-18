import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'logto-auth-session',
  description: 'Session lifetime, refresh rotation, reuse detection, and re-mint behavior are proven.',
  command: 'nix develop .#ci -c flutter test test/auth_onboarding_test.dart',
  file: 'lib/auth/session_controller.dart',
  find: 'next.refreshToken == current.refreshToken',
  replace: 'next.refreshToken != current.refreshToken',
});
