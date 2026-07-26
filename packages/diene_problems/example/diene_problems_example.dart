import 'package:diene_problems/diene_problems.dart';

/// Demonstrates the clean consumer path through the public barrel alone:
/// declare problem types once, mint every `type` URI through the ONE builder,
/// and export the per-endpoint catalog the edge error portal publishes.
Future<void> main() async {
  // 1. The portal is config, never a hardcoded string (R4). A real Flutter app
  //    sources these LPSM segments from build-time `--dart-define` once
  //    `diene_config` lands; here they are literal for the sake of the example.
  const ErrorPortal portal = ErrorPortal(
    scheme: 'https',
    host: 'docs.raichu.cluster.atomi.cloud',
    landscape: 'raichu',
    platform: 'dotnet',
    service: 'user',
    module: 'api',
  );

  // 2. Register the portable generics. Domain problems stay in the service that
  //    owns them; wire ids are snake_case per R-E14.
  final ProblemRegistry registry = ProblemRegistry(portal);
  GenericProblems.registerAll(registry);

  final ProblemType notFound = registry.require('entity_not_found');
  assert(
    registry.typeUriFor(notFound) ==
        'https://docs.raichu.cluster.atomi.cloud/docs/raichu/dotnet/user/api'
            '/v1/entity_not_found',
    'the registry resolves type URIs through the single builder',
  );

  // 3. A runtime envelope round-trips through the RFC 9457 wire form.
  final Problem problem = Problem(
    type: registry.typeUriFor(notFound),
    title: notFound.title,
    status: notFound.status ?? 500,
    detail: 'User 42 does not exist',
    instance: '/user/42',
    recoverable: notFound.recoverable,
    data: const <String, Object?>{'resource': 'user', 'id': 42},
  );
  assert(
    Problem.fromJson(problem.toJson()) == problem,
    'the codec round-trips',
  );

  // 4. Any value folds into a Problem — the transformer never throws.
  final Problem folded = fromObject(<String, Object?>{
    'problemId': 'validation_error',
    'data': <String, Object?>{'fields': <Object?>[]},
  }, options: TransformOptions(portal: portal, registry: registry));
  assert(folded.status == 400, 'the registry supplied the catalogued status');

  final Problem unknown = fromObject(StateError('nothing matched'));
  assert(
    unknown.type.endsWith('/v1/$uncataloguedProblemId'),
    'an unknown value becomes an uncatalogued 5xx problem (C0 §14)',
  );

  // 5. Unexpected client-side exceptions become a LocalError Problem the
  //    flutter-base visualizer renders; production forwards captures to Faro.
  final Problem local = await LocalError(
    const NoopErrorSink(),
    portal: portal,
  ).wrap(StateError('render failed'), StackTrace.current);
  assert(local.data.containsKey('stackTrace'), 'the stack trace is carried');

  // 6. Catalog EXPORT: the producer side of the edge error portal. Each entry
  //    ships `recoverable` + `endpoints` alongside id/type/status/data, which is
  //    what the per-service × landscape Problem CR payload carries.
  final ProblemCatalog catalog = ProblemCatalog(portal: portal)
    ..addType(
      notFound,
      endpoints: const <CatalogEndpoint>[
        CatalogEndpoint(method: 'GET', path: '/user/{id}'),
      ],
    )
    ..addType(
      registry.require('validation_error'),
      endpoints: const <CatalogEndpoint>[
        CatalogEndpoint(method: 'POST', path: '/user'),
      ],
    );

  final List<Map<String, Object?>> crd = catalog.toCrdContent();
  assert(crd.length == 2, 'both problems are catalogued');
  assert(crd.first['recoverable'] == false, 'the classifier flag is exported');

  // 7. The frozen C0 contract travels with the package, so consumers can assert
  //    which authenticated release this build was projected from.
  assert(
    c0ProblemContract.provenance.releaseId.startsWith('c0-fixtures-r'),
    'the generated projection names its release',
  );
}
