// Wire two backends on the LPSM client tree, call one, and handle the outcome as
// a Result<T, Problem>. Nothing here throws: every fallible step returns a
// Result, and a Problem is data, not an exception.
//
// `print` is the right output for a runnable example, so the production-code lint
// is waived for this file only.
// ignore_for_file: avoid_print
import 'package:diene_api_engine/diene_api_engine.dart';

Future<void> main() async {
  // Each registered backend is ONE hostname. Resilience on the hot path is
  // retry-once-on-network-error, not an always-on failover ladder.
  final BackendConfig core = BackendConfig(
    coordinate: const LpsmCoordinate(
      landscape: 'raichu',
      platform: 'diene',
      service: 'api',
      module: 'core',
    ),
    baseUrl: Uri.parse('https://core.raichu.cluster.atomi.cloud'),
    resourceName: 'https://core.raichu.cluster.atomi.cloud',
  );
  final BackendConfig billing = BackendConfig(
    coordinate: const LpsmCoordinate(
      landscape: 'raichu',
      platform: 'diene',
      service: 'api',
      module: 'billing',
    ),
    baseUrl: Uri.parse('https://billing.raichu.cluster.atomi.cloud'),
    resourceName: 'https://billing.raichu.cluster.atomi.cloud',
  );

  // The rescue router is DORMANT: it engages only after a hard connect failure
  // survives the single retry. The issuer is BAKED build-time config and is never
  // taken from a fetched document, and every doc-sourced URL is checked against
  // the baked endpoint-suffix allowlist at the moment of use.
  final ApiEngineConfig config = ApiEngineConfig(
    backends: <BackendConfig>[core, billing],
    rescue: RescueConfig(
      enabled: true,
      issuer: Uri.parse('https://auth.raichu.cluster.atomi.cloud'),
      catalogHosts: const <String>['https://rescue-seed.atomi.cloud'],
      endpointSuffixAllowlist: const <String>['.raichu.cluster.atomi.cloud'],
    ),
  );

  // Pass `auth:` to resolve per-backend tokens through the diene_auth_engine
  // IAuth seam; omitted here so the example needs no identity provider.
  final ApiEngine engine = ApiEngine.fromConfig(config);

  final Backend? backend = engine.backend(core.coordinate);
  if (backend == null) {
    return;
  }

  final Result<Map<String, Object?>> result = await backend
      .call<Map<String, Object?>>(
        method: HttpMethod.get,
        path: '/user/42',
        decode: (Map<String, Object?> json) => json,
      );

  switch (result) {
    case Ok<Map<String, Object?>>(:final value):
      print('user: $value');
    case Err<Map<String, Object?>>(:final problem):
      // An RFC 9457 envelope, including whether the caller may retry.
      print(
        'failed ${problem.status}: ${problem.title} '
        '(recoverable: ${problem.recoverable})',
      );
  }
}
