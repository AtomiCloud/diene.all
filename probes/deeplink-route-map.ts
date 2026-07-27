import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'deeplink-route-map',
  description: 'The app<->web route map is a well-formed invertible mapping, pinned to the nextjs counterpart.',
  command: 'nix develop .#ci -c flutter test test/routing_route_map_test.dart',
  file: 'lib/routing/route_map.dart',
  // Add one unmapped route whose halves declare different parameter sets. The
  // param-set invariant is by NAME, not position, so this is a real violation
  // rather than a reordering.
  find: "  DeeplinkRoute(id: RouteIds.profile, web: '/profile', app: '/profile'),",
  replace:
    "  DeeplinkRoute(id: RouteIds.profile, web: '/profile', app: '/profile'),\n" +
    "  DeeplinkRoute(id: 'orphan', web: '/orphan', app: '/orphan/:id'),",
});
