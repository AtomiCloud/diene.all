// Production dead-code root for the published diene_problems surface.
//
// This is tooling, not a test. dart_code_linter otherwise treats only the
// public barrel (diene_problems.dart) as an entrypoint and incorrectly reports
// the test_helper.dart public members as unused. Referencing every public
// export here keeps the production-only dead-code pass honest without any
// exclusion list. deadcode.sh copies this file to bin/main.dart inside the
// production-only sandbox, so it lives in the member package where
// `package:diene_problems` resolves cleanly (and is excluded from the published
// archive by .pubignore).
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_problems/test_helper.dart';

Future<void> main() async {
  // The ONE type-URI builder, its portal, and its R-E14 wire-id law.
  final ErrorPortal portal = anErrorPortal();
  final String typeUri = problemTypeUri(
    portal: portal,
    version: 'v1',
    id: 'entity_not_found',
  );
  if (!problemSegmentPattern.hasMatch(portal.landscape) ||
      !problemWireIdPattern.hasMatch(r14WireId('entity-not-found')) ||
      !problemVersionPattern.hasMatch('v1') ||
      ErrorPortal.localError.module.isEmpty) {
    throw StateError('unexpected type-URI contract');
  }
  try {
    problemTypeUri(portal: portal, version: 'v1', id: 'entity-not-found');
    throw StateError('a kebab wire id must be rejected');
  } on InvalidProblemTypeSegmentError catch (error) {
    if (error.name == null) rethrow;
  }

  // The envelope and its wire codec.
  final Problem problem = Problem(
    type: typeUri,
    title: 'Entity not found',
    status: 404,
    detail: 'missing',
    instance: '/user/42',
    data: const <String, Object?>{'resource': 'user'},
  );
  if (Problem.fromJson(problem.toJson()) != problem ||
      problem.hashCode == 0 ||
      problem.toString().isEmpty ||
      problem.recoverable ||
      uncataloguedProblemId.isEmpty) {
    throw StateError('unexpected envelope behaviour');
  }

  // The typed registry and the portable generic set.
  final ProblemRegistry registry = ProblemRegistry(portal, GenericProblems.all);
  final ProblemType required = registry.require('entity_not_found');
  if (registry.lookup('conflict') == null ||
      registry.entries.length != GenericProblems.all.length ||
      registry.typeUriFor(required) != typeUri ||
      required.dataSchema.isEmpty ||
      GenericProblems.validationError.recoverable != true ||
      GenericProblems.entityNotFound.status != 404 ||
      GenericProblems.conflict.status != 409 ||
      GenericProblems.unauthenticated.status != 401 ||
      GenericProblems.unauthorized.status != 403 ||
      GenericProblems.invalidJson.status != 400 ||
      required.version.isEmpty ||
      required.title.isEmpty) {
    throw StateError('unexpected registry behaviour');
  }
  try {
    registry.register(GenericProblems.conflict);
    throw StateError('a duplicate id must be rejected');
  } on DuplicateProblemTypeError catch (error) {
    if (error.message.isEmpty) rethrow;
  }
  try {
    registry.require('never_registered');
    throw StateError('an unknown id must be rejected');
  } on UnknownProblemTypeError catch (error) {
    if (error.message.isEmpty) rethrow;
  }
  final ProblemRegistry empty = ProblemRegistry(portal)
    ..register(GenericProblems.conflict);
  if (empty.entries.isEmpty) {
    throw StateError('unexpected empty registry');
  }
  GenericProblems.registerAll(ProblemRegistry(portal));

  // The transformer.
  final TransformOptions options = TransformOptions(
    portal: portal,
    registry: registry,
    defaultStatus: 500,
    defaultVersion: 'v1',
  );
  if (fromObject(problem) != problem ||
      fromObject(<String, Object?>{
            'problemId': 'validation_error',
            'data': <String, Object?>{'fields': <Object?>[]},
          }, options: options).status !=
          400 ||
      !fromObject(
        StateError('x'),
        options: options,
      ).type.endsWith(uncataloguedProblemId) ||
      options.defaultVersion.isEmpty ||
      options.defaultStatus != 500 ||
      options.registry == null ||
      options.portal.service.isEmpty) {
    throw StateError('unexpected transformer behaviour');
  }

  // LocalError wrapping and both shipped sinks.
  final _Sink sink = _Sink();
  final Problem local = await LocalError(
    sink,
    portal: portal,
  ).wrap(StateError('boom'), StackTrace.empty);
  await const NoopErrorSink().capture(local);
  if (sink.count != 1 || !local.data.containsKey('stackTrace')) {
    throw StateError('unexpected local-error behaviour');
  }

  // Catalog EXPORT, the producer side of the edge error portal.
  final ProblemCatalog catalog = ProblemCatalog(portal: portal)
    ..addGenerics()
    ..add(
      aCatalogEntry(
        id: 'entity_not_found',
        endpoints: const <CatalogEndpoint>[
          CatalogEndpoint(method: 'GET', path: '/user/{id}'),
        ],
      ),
    )
    ..addType(
      GenericProblems.conflict,
      endpoints: const <CatalogEndpoint>[
        CatalogEndpoint(method: 'PUT', path: '/user/{id}'),
      ],
    );
  final CatalogEntry? entry = catalog.lookup('entity_not_found');
  if (entry == null ||
      entry.typeUri.isEmpty ||
      entry.title.isEmpty ||
      entry.status != 404 ||
      entry.recoverable ||
      entry.dataSchema.isNotEmpty ||
      entry.endpoints.single.toJson()['method'] != 'GET' ||
      entry.endpoints.single.path.isEmpty ||
      entry.toCrdContent()['id'] != 'entity_not_found' ||
      catalog.entries.isEmpty ||
      catalog.toCrdContent().isEmpty ||
      catalog.portal.host.isEmpty) {
    throw StateError('unexpected catalog behaviour');
  }

  // The generated, digest-authenticated C0 projection.
  const C0ProblemContract contract = c0ProblemContract;
  if (contract.provenance.releaseId.isEmpty ||
      contract.provenance.contractVersion < 1 ||
      contract.provenance.releaseDigest.isEmpty ||
      contract.provenance.c0ProseSource.path.isEmpty ||
      contract.provenance.c0ProseSource.sha256.isEmpty ||
      contract.provenance.c0ProseSource.note == null ||
      contract.provenance.secondarySources.isEmpty ||
      contract.provenance.formatterPolicyPath.isEmpty ||
      contract.provenance.formatterPolicySha256.isEmpty ||
      contract.provenance.prettierExcludedPaths.isEmpty ||
      contract.c0Sections.isEmpty ||
      contract.rfc9457Members.isEmpty ||
      contract.extensions.isEmpty ||
      contract.typeUriTemplate.isEmpty ||
      contract.typeUri.isEmpty ||
      contract.envelopes.isEmpty ||
      contract.catalogEntry.isEmpty) {
    throw StateError('unexpected C0 projection');
  }

  // Accept a known-good envelope through the shipped TestHelper…
  expectProblem(
    aProblem(portal: portal, data: const <String, Object?>{'resource': 'user'}),
    title: 'Entity not found',
    status: 404,
    recoverable: false,
    data: const <String, Object?>{'resource': 'user'},
  );
  expectProblem(
    problem,
    type: typeUri,
    detail: 'missing',
    instance: '/user/42',
  );

  // …and prove the failure type is reachable by rejecting a known-bad one.
  try {
    expectProblem(problem, status: 500);
    throw StateError('a mismatched envelope must be rejected');
  } on ProblemMatcherError catch (error) {
    if (error.message == null) rethrow;
  }
}

final class _Sink implements ErrorSink {
  int count = 0;

  @override
  Future<void> capture(Problem problem) async => count += 1;
}
