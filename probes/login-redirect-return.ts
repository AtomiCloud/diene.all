import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'login-redirect-return',
  description: 'A protected deeplink preserves target path AND query through login, then returns to it.',
  command:
    "nix develop .#ci -c flutter test test/routing_login_redirect_test.dart --plain-name 'login redirect return'",
  file: 'lib/routing/app_router.dart',
  // Carry only the path and drop the query. This is the sabotage that LOOKS
  // like a working redirect while silently losing the filters the link was
  // about — which is exactly why the query half is asserted separately.
  find: 'return buildLoginLocation(loginPath, location);',
  replace: 'return buildLoginLocation(loginPath, target.path);',
});
