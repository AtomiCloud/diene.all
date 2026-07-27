/// Presence row for the published lib/dart dependency declarations.
///
/// The E4-final assembly consumes the `diene_<name>` packages published from the
/// `AtomiCloud/diene.dart_<name>` mirrors. Until `lib/dart/e2e` obtains an
/// accepted sha those points are HELD, and the hold is expressed in code by
/// `lib/integration/e4_manifest.dart` rather than only in prose.
///
/// This row therefore asserts what is actually declared TODAY: the manifest
/// enumerates every diene package the swap-in will introduce, each held point
/// names a concrete `diene_*` package, and the pubspec is internally consistent
/// with that state. A presence row reports exists/parses only — it has no
/// sabotage.
const manifest = 'lib/integration/e4_manifest.dart';

// Every diene package the E4-final assembly declares a dependency on.
const declaredPackages = [
  'diene_result',
  'diene_problems',
  'diene_config',
  'diene_core_utils',
  'diene_auth_engine',
  'diene_api_engine',
] as const;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'presence-published-lib-dart-dependencies',
      description: 'The declared pub.dev diene package dependencies exist in the manifest and parse.',
      kind: 'baseline',
      async run(repo: any) {
        if ((await repo.glob(manifest)).length !== 1) {
          throw new Error(`missing the E4 integration manifest: ${manifest}`);
        }
        if ((await repo.glob('pubspec.yaml')).length !== 1) {
          throw new Error('missing pubspec.yaml');
        }

        const source = await repo.read(manifest);
        // Assert the declaration, not merely that the file mentions the name:
        // each package must be named on the dienePackage side of an integration
        // point. Points may carry more than one package (diene_config and
        // diene_core_utils share one), so collect the declared side and test
        // membership rather than requiring each name to start its own point.
        const declared = Array.from(
          source.matchAll(/dienePackage:\s*'([^']*)'/g),
          (match: RegExpMatchArray) => match[1],
        ).join('\n');
        if (declared.length === 0) {
          throw new Error(`${manifest} declares no integration points at all`);
        }
        for (const value of declaredPackages) {
          if (!declared.includes(value)) {
            throw new Error(`the integration manifest declares no dependency on ${value}`);
          }
        }

        // Every package delivered via lib/dart/e2e is held until that sha is
        // accepted. A manifest with no held points would mean the swap-in has
        // landed, and this row would then be asserting a stale contract.
        const heldPoints = source.match(/held: true/g) ?? [];
        if (heldPoints.length === 0) {
          throw new Error(
            'the manifest declares no held integration points; the lib/dart swap-in has landed and this row needs re-basing',
          );
        }

        const pubspec = await repo.read('pubspec.yaml');
        // The template publishes nothing itself, and pinning that keeps a
        // pub.dev consumer from being mistaken for a pub.dev publisher.
        if (!pubspec.includes('publish_to: none')) {
          throw new Error('pubspec.yaml no longer declares publish_to: none');
        }
      },
    },
  ],
};
