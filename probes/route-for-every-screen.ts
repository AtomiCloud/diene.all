import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'route-for-every-screen',
  description: 'Every declared screen has a route-map entry; declared ids are a subset of the map.',
  command:
    "nix develop .#ci -c flutter test test/routing_login_redirect_test.dart --plain-name 'route-for-every-screen'",
  file: 'lib/screens/app_screens.dart',
  // Add a REAL screen with no route-map entry. The registry is the single place
  // a screen can be reached from, so this is genuinely unreachable-by-link.
  find: 'final List<ScreenDefinition> appScreens = <ScreenDefinition>[',
  replace:
    'final List<ScreenDefinition> appScreens = <ScreenDefinition>[\n' +
    '  ScreenDefinition(\n' +
    "    routeId: 'unrouted',\n" +
    "    title: 'Unrouted',\n" +
    '    builder: (BuildContext context, ScreenRouteContext route) =>\n' +
    '        const OnboardingScreen(),\n' +
    '  ),',
});
