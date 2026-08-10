import 'dart:convert';
import 'dart:io';

import 'package:diene_config/diene_config.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

import '../../tool/gen_c0_projection.dart'
    show
        C0AuthenticatedRelease,
        C0ReleaseAuthenticationFailure,
        authenticateC0Release,
        c0ReleaseDigestDomain,
        c0ReleaseDigestOf,
        c0ReleaseLedgerPath,
        c0ReleaseManifestPath,
        canonicalCompactJson,
        parseC0Ledger,
        renderNormativeCaseBytes,
        sha256HexOf;
import '../support.dart';

/// C0 §3 config-precedence conformance, driven from the FROZEN C0 release.
///
/// The vectors are not written here: they are projected from
/// `contracts/c0/cases/config.json` (release `c0-fixtures-r2`) by
/// `tool/gen_c0_projection.dart` into `test/fixtures/c0/config.json`. This suite
/// reads that projection, so a change to the normative release either flows
/// through or reddens the projection check — it cannot be silently diverged
/// from by editing an assertion in this file.
///
/// **The projection is authenticated, not trusted.** Comparing the fixture's
/// `releaseDigest` field to the contract's would only compare two copies of a
/// string, and a fixture that carries its own checksum only proves it was
/// rendered in one piece. So the binding group RE-DERIVES the release: it
/// re-renders the normative case bytes from the very vectors the suite below
/// drives, requires the embedded `contracts/c0/SHA256SUMS` bytes to record that
/// hash, requires the ledger plus the embedded manifest witness to hash to the
/// complete-release digest, and requires THAT digest to be the one
/// `c0ConfigContract` accepts. It also byte-compares the re-rendered case and
/// both witnesses against the frozen release in the repository. `fails closed`
/// below forges an edited case with a regenerated ledger, digest and checksum —
/// internally consistent in every way — and shows the gate still refuses it.
///
/// The derivation helpers come from the generator rather than being copied
/// here: a second implementation of the digest recipe is a second thing to
/// drift, and a divergence would be invisible precisely when it mattered. What
/// the suite does not take from the generator is its output — every hash it
/// checks is recomputed from bytes.
///
/// Unlike the `diene_core_utils` conformance suite, which projects only the
/// four mechanics that package implements, this one binds ALL FIVE vectors: the
/// `finalLayerValidation` case is the one core-utils leaves to its consumer,
/// and `diene_config` is that consumer.
///
/// The vectors' YAML is fed through the REAL [YamlConfigSource], and the
/// layering through the REAL [ConfigLoader]: this suite proves the shipped
/// loader conforms, not that a test-local reimplementation does.
const String _fixturePath = 'test/fixtures/c0/config.json';
const String _checksumPath = 'test/fixtures/c0/SHA256SUMS';

/// The repository root, relative to the member directory the suite runs in.
const String _repositoryRoot = '../..';

/// A forged release: edited normative case bytes, the ledger and the
/// complete-release digest they imply, and the internally consistent projection
/// a forger would commit alongside them.
typedef _Forgery = ({
  String caseText,
  String ledgerText,
  String digest,
  String fixtureText,
});

void main() {
  final String fixtureText = File(_fixturePath).readAsStringSync();
  final Map<String, Object?> fixture = _object(fixtureText, _fixturePath);
  final Map<String, Object?> generated =
      (fixture[r'$generated']! as Map<Object?, Object?>)
          .cast<String, Object?>();
  final C0ConfigProvenance pin = c0ConfigContract.provenance;

  /// One `$generated` string, or a failure naming the field that went missing.
  String field(String name) {
    final Object? value = generated[name];
    expect(
      value,
      isA<String>(),
      reason: 'the projection lost \$generated.$name',
    );
    return value! as String;
  }

  /// The normative case bytes, re-rendered from the vectors this suite drives.
  ///
  /// The frozen case files are pretty-canonical and hold nothing but `domain`,
  /// `c0Sections` and the projected vectors, so this reproduces their exact
  /// bytes — and a vector that was edited, dropped or reordered changes the
  /// hash the ledger has to match.
  String projectedCaseBytes() => renderNormativeCaseBytes(
    domain: field('domain'),
    c0Sections: fixture['c0Sections'],
    cases: <String, Object?>{
      for (final String name in c0ConfigContract.projectedCases)
        name: fixture[name],
    },
  );

  group('C0 release binding', () {
    test(
      'the fixture is the authenticated projection of the pinned release',
      () {
        // Act — re-derive the release from the fixture's own bytes.
        final C0AuthenticatedRelease release = authenticateC0Release(
          manifestWithoutDigest: field('releaseManifestWithoutDigest'),
          ledgerText: field('releaseLedger'),
          caseText: projectedCaseBytes(),
          pin: pin,
          projectedCases: c0ConfigContract.projectedCases,
        );

        // Assert
        expect(
          release.releaseDigest,
          pin.releaseDigest,
          reason:
              'the projected vectors and their witnesses do not hash to the '
              'release this package accepts',
        );
        expect(release.caseSha256, field('sourceCaseSha256'));
        expect(
          field('releaseId'),
          pin.releaseId,
          reason:
              'the projection came from a DIFFERENT release than the '
              'contract this package claims to bind',
        );
        expect(field('releaseDigest'), pin.releaseDigest);
        expect(field('sourceCase'), pin.sourceCase);
        expect(field('domain'), 'config');
        expect(field('releaseDigestDomain'), c0ReleaseDigestDomain);
        expect(field('releaseManifestPath'), c0ReleaseManifestPath);
        expect(field('releaseLedgerPath'), c0ReleaseLedgerPath);
        expect(field('releaseLedgerEntry'), release.ledgerEntry);
        expect(fixture['c0Sections'], pin.c0Sections);

        // The local ledger must authenticate the exact bytes just parsed.
        // Comparing the VALUES keeps this from passing on a truncated ledger.
        expect(
          File(_checksumPath).readAsStringSync(),
          '${sha256HexOf(fixtureText)}  config.json\n',
        );
      },
    );

    test('the projected vectors ARE the frozen release bytes', () {
      // The chain above closes on the pinned digest without reading a single
      // repository file, which is what makes it unforgeable. This adds the
      // other half: the bytes it authenticated are the committed ones, so a
      // projection cannot drift from `contracts/c0/` while staying green.
      // Arrange
      final String casePath = '$_repositoryRoot/${pin.sourceCase}';
      final Map<String, Object?> manifest = _object(
        File('$_repositoryRoot/$c0ReleaseManifestPath').readAsStringSync(),
        c0ReleaseManifestPath,
      );

      // Assert
      expect(
        projectedCaseBytes(),
        File(casePath).readAsStringSync(),
        reason: 'the projection is not a byte-faithful image of $casePath',
      );
      expect(
        field('releaseLedger'),
        File('$_repositoryRoot/$c0ReleaseLedgerPath').readAsStringSync(),
        reason: 'the embedded ledger is not the committed release ledger',
      );
      expect(manifest.remove('releaseDigest'), pin.releaseDigest);
      expect(
        canonicalCompactJson(manifest),
        field('releaseManifestWithoutDigest'),
        reason: 'the embedded manifest witness is not the committed manifest',
      );
    });

    test('the release id and contract version agree', () {
      // Assert
      expect(pin.releaseId, 'c0-fixtures-r${pin.contractVersion}');
    });

    test('every vector this package claims is present and non-empty', () {
      // Refuse to judge on missing data: a vector that vanished from the
      // projection would otherwise make its group below silently vacuous.
      // Assert
      expect(
        (generated['projectedCases']! as List<Object?>).cast<String>(),
        c0ConfigContract.projectedCases,
      );
      for (final String name in c0ConfigContract.projectedCases) {
        expect(fixture[name], isNotNull, reason: 'vector $name is missing');
        expect(
          (fixture[name]! as Map<Object?, Object?>).isNotEmpty,
          isTrue,
          reason: 'vector $name is empty',
        );
      }
    });

    test('it binds the finalLayerValidation vector core-utils omits', () {
      // This is the ownership boundary in one assertion: validating the merged
      // layer is this package's job, so this vector must be bound HERE.
      // Assert
      expect(c0ConfigContract.projectedCases, contains('finalLayerValidation'));
    });
  });

  group('C0 release binding fails closed', () {
    /// Forges the release an edited normative case would produce.
    ///
    /// This is the laundering path R-E24a rejects, performed in full: a §3
    /// vector is edited, its new hash is written into the release ledger, the
    /// projection is re-rendered, and the accepted `releaseDigest` STRING is
    /// retained so every metadata comparison still matches. With
    /// [rehashLedger] false the ledger is left alone instead, which isolates
    /// the case-bytes binding from the digest binding.
    _Forgery forgeEditedCase({required bool rehashLedger}) {
      final Map<String, Object?> vectors = <String, Object?>{
        for (final String name in c0ConfigContract.projectedCases)
          name: _clone(fixture[name]),
      };
      // §3 says a blank define leaves the base value alone; the forged vector
      // expects a different base value, so a package that obeys §3 would now
      // be judged against a rule the release never authorized.
      final Map<String, Object?> expected =
          (vectors['blankIsUnset']! as Map<String, Object?>)['expected']!
              as Map<String, Object?>;
      expected['retries'] = 99;

      final String caseText = renderNormativeCaseBytes(
        domain: field('domain'),
        c0Sections: fixture['c0Sections'],
        cases: vectors,
      );
      final String caseSha256 = sha256HexOf(caseText);
      final String ledgerText = rehashLedger
          ? field(
              'releaseLedger',
            ).replaceFirst(field('sourceCaseSha256'), caseSha256)
          : field('releaseLedger');
      final Map<String, Object?> forged = <String, Object?>{
        r'$generated': <String, Object?>{
          ...generated,
          'sourceCaseSha256': caseSha256,
          'releaseLedger': ledgerText,
        },
        'c0Sections': fixture['c0Sections'],
        ...vectors,
      };
      return (
        caseText: caseText,
        ledgerText: ledgerText,
        digest: c0ReleaseDigestOf(
          manifestWithoutDigest: field('releaseManifestWithoutDigest'),
          ledgerText: ledgerText,
        ),
        fixtureText: '${const JsonEncoder.withIndent('  ').convert(forged)}\n',
      );
    }

    /// Authenticates arbitrary bytes against an accepted release identity.
    C0AuthenticatedRelease authenticate({
      required String caseText,
      required String ledgerText,
      String? manifestWithoutDigest,
      String? releaseDigest,
    }) => authenticateC0Release(
      manifestWithoutDigest:
          manifestWithoutDigest ?? field('releaseManifestWithoutDigest'),
      ledgerText: ledgerText,
      caseText: caseText,
      pin: releaseDigest == null
          ? pin
          : C0ConfigProvenance(
              releaseId: pin.releaseId,
              contractVersion: pin.contractVersion,
              releaseDigest: releaseDigest,
              sourceCase: pin.sourceCase,
              c0Sections: pin.c0Sections,
            ),
      projectedCases: c0ConfigContract.projectedCases,
    );

    test('an edited normative case cannot be laundered into a green '
        'self-consistent fixture', () {
      // Arrange
      final _Forgery forgery = forgeEditedCase(rehashLedger: true);
      final Map<String, Object?> forgedFixture = _object(
        forgery.fixtureText,
        'the forged projection',
      );
      final Map<String, Object?> forgedGenerated =
          (forgedFixture[r'$generated']! as Map<Object?, Object?>)
              .cast<String, Object?>();

      // Assert — the forgery really did change a vector, and it is consistent
      // with itself everywhere a LOCAL check could look: the metadata still
      // names the accepted release and digest, the embedded ledger records the
      // hash of the edited case, and a regenerated local checksum would match
      // the rendered bytes.
      expect(forgery.fixtureText, isNot(fixtureText));
      expect(
        _vector(forgedFixture, 'blankIsUnset')['expected'],
        isNot(_vector(fixture, 'blankIsUnset')['expected']),
      );
      expect(forgedGenerated['releaseId'], pin.releaseId);
      expect(forgedGenerated['releaseDigest'], pin.releaseDigest);
      expect(forgedGenerated['sourceCase'], pin.sourceCase);
      expect(
        forgedGenerated['sourceCaseSha256'],
        sha256HexOf(forgery.caseText),
      );
      expect(
        parseC0Ledger(
          forgery.ledgerText,
        )[forgedGenerated['releaseLedgerEntry']],
        sha256HexOf(forgery.caseText),
      );
      expect(forgery.digest, isNot(pin.releaseDigest));

      // Act + Assert — and the gate still refuses it, because the digest is
      // RE-DERIVED from the ledger rather than read out of the fixture.
      expect(
        () => authenticate(
          caseText: forgery.caseText,
          ledgerText: forgery.ledgerText,
        ),
        throwsA(
          isA<C0ReleaseAuthenticationFailure>().having(
            (C0ReleaseAuthenticationFailure failure) => failure.reason,
            'reason',
            allOf(contains(forgery.digest), contains(pin.releaseDigest)),
          ),
        ),
      );
    });

    test('the SAME forged bytes authenticate only against a forged accepted '
        'identity', () {
      // The mirror of the test above: the refusal comes from the release
      // identity and nothing else, so laundering an edited case requires
      // editing the accepted digest in lib/src/c0_config_contract.dart — which
      // scripts/validate/c0-release.sh pins independently, together with the
      // release commit. That edit is the reviewable act; this test says so out
      // loud rather than leaving it implied.
      // Arrange
      final _Forgery forgery = forgeEditedCase(rehashLedger: true);

      // Act
      final C0AuthenticatedRelease forged = authenticate(
        caseText: forgery.caseText,
        ledgerText: forgery.ledgerText,
        releaseDigest: forgery.digest,
      );

      // Assert
      expect(forged.releaseDigest, forgery.digest);
      expect(forged.releaseDigest, isNot(pin.releaseDigest));
      expect(
        (forged.cases['blankIsUnset']! as Map<String, Object?>)['expected'],
        isNot(_vector(fixture, 'blankIsUnset')['expected']),
      );
    });

    test(
      'an edited case with the ORIGINAL ledger fails on the ledger entry',
      () {
        // Arrange — the digest chain is untouched here, which isolates the
        // case-bytes binding: the ledger is still the accepted one.
        final _Forgery forgery = forgeEditedCase(rehashLedger: false);

        // Assert
        expect(forgery.digest, pin.releaseDigest);
        expect(
          () => authenticate(
            caseText: forgery.caseText,
            ledgerText: forgery.ledgerText,
          ),
          throwsA(
            isA<C0ReleaseAuthenticationFailure>().having(
              (C0ReleaseAuthenticationFailure failure) => failure.reason,
              'reason',
              allOf(
                contains(c0ReleaseLedgerPath),
                contains(field('releaseLedgerEntry')),
              ),
            ),
          ),
        );
      },
    );

    test('a ledger that omits the normative case cannot authenticate it', () {
      // Arrange — pinned to the stripped ledger's own digest, so the identity
      // check passes and the missing entry is what fails.
      final List<String> lines = field('releaseLedger').split('\n')
        ..removeLast()
        ..removeWhere(
          (String line) => line.endsWith('  ${field('releaseLedgerEntry')}'),
        );
      final String stripped = '${lines.join('\n')}\n';

      // Assert
      expect(
        () => authenticate(
          caseText: projectedCaseBytes(),
          ledgerText: stripped,
          releaseDigest: c0ReleaseDigestOf(
            manifestWithoutDigest: field('releaseManifestWithoutDigest'),
            ledgerText: stripped,
          ),
        ),
        throwsA(
          isA<C0ReleaseAuthenticationFailure>().having(
            (C0ReleaseAuthenticationFailure failure) => failure.reason,
            'reason',
            contains('no entry for ${field('releaseLedgerEntry')}'),
          ),
        ),
      );
    });

    test('a manifest witness that carries its own digest is refused', () {
      // A witness containing the digest it is supposed to prove is circular:
      // the release recipe hashes the manifest WITHOUT it.
      // Arrange
      final Map<String, Object?> witness = _object(
        field('releaseManifestWithoutDigest'),
        'the manifest witness',
      );
      witness['releaseDigest'] = pin.releaseDigest;

      // Assert
      expect(
        () => authenticate(
          caseText: projectedCaseBytes(),
          ledgerText: field('releaseLedger'),
          manifestWithoutDigest: canonicalCompactJson(witness),
        ),
        throwsA(
          isA<C0ReleaseAuthenticationFailure>().having(
            (C0ReleaseAuthenticationFailure failure) => failure.reason,
            'reason',
            contains('releaseDigest'),
          ),
        ),
      );
    });

    test('a re-ordered manifest witness is refused', () {
      // Same content, different bytes: the digest authenticates BYTES, so a
      // witness that is not compact-canonical is refused before it is hashed.
      // Arrange
      final Map<String, Object?> witness = _object(
        field('releaseManifestWithoutDigest'),
        'the manifest witness',
      );
      final Object? releaseId = witness.remove('releaseId');
      final String reordered = jsonEncode(<String, Object?>{
        'releaseId': releaseId,
        ...witness,
      });

      // Assert
      expect(reordered, isNot(field('releaseManifestWithoutDigest')));
      expect(
        () => authenticate(
          caseText: projectedCaseBytes(),
          ledgerText: field('releaseLedger'),
          manifestWithoutDigest: reordered,
        ),
        throwsA(
          isA<C0ReleaseAuthenticationFailure>().having(
            (C0ReleaseAuthenticationFailure failure) => failure.reason,
            'reason',
            contains('compact-canonical'),
          ),
        ),
      );
    });

    test('a malformed, unterminated or duplicated ledger is refused', () {
      // A lenient parser that skipped these lines would authenticate whatever
      // survived, so the grammar itself fails closed.
      // Arrange
      const String hash =
          '0000000000000000000000000000000000000000000000000000000000000000';

      // Assert
      expect(
        () => parseC0Ledger('not a ledger line\n'),
        throwsA(isA<C0ReleaseAuthenticationFailure>()),
      );
      expect(
        () => parseC0Ledger('$hash  cases/config.json'),
        throwsA(isA<C0ReleaseAuthenticationFailure>()),
      );
      expect(
        () => parseC0Ledger(''),
        throwsA(isA<C0ReleaseAuthenticationFailure>()),
      );
      expect(
        () => parseC0Ledger(
          '$hash  cases/config.json\n$hash  cases/config.json\n',
        ),
        throwsA(isA<C0ReleaseAuthenticationFailure>()),
      );
      expect(parseC0Ledger('$hash  cases/config.json\n'), <String, String>{
        'cases/config.json': hash,
      });
    });
  });

  group('C0 §3 layering and indexed lists', () {
    test(
      'base, landscape, and define layers apply in precedence order',
      () async {
        // Arrange
        final Map<String, Object?> vector = _vector(
          fixture,
          'layeringAndIndexedList',
        );

        // Act
        final Result<DieneConfig> loaded = await _load(
          vector,
          overlayKey: 'landscapeYaml',
        );

        // Assert
        expect(loaded, isOk, reason: describe(loaded));
        expect(loaded.unwrap().rawSlice('app').unwrap(), vector['expected']);
      },
    );

    test(
      'the development layer sits between the overlay and the defines',
      () async {
        // With the development layer present, its `tags` beats the landscape
        // layer's and is in turn beaten by the indexed defines.
        // Arrange
        final Map<String, Object?> vector = _vector(
          fixture,
          'layeringAndIndexedList',
        );

        // Act
        final Result<DieneConfig> loaded = await _load(
          vector,
          overlayKey: 'landscapeYaml',
          developmentKey: 'developmentYaml',
        );

        // Assert
        expect(loaded, isOk, reason: describe(loaded));
        // The expected tree is unchanged: the defines override the development
        // layer's own name and tags, which is precisely the ordering claim.
        expect(loaded.unwrap().rawSlice('app').unwrap(), vector['expected']);
      },
    );

    test(
      'the development layer DOES win when no define covers its key',
      () async {
        // Without the define layer the development values survive, proving the
        // previous test's result comes from ordering rather than from the
        // development layer being ignored altogether.
        // Arrange
        final Map<String, Object?> vector = _vector(
          fixture,
          'layeringAndIndexedList',
        );

        // Act
        final Result<DieneConfig> loaded = await _load(
          vector,
          overlayKey: 'landscapeYaml',
          developmentKey: 'developmentYaml',
          defines: const <String, String>{},
        );

        // Assert
        expect(loaded, isOk, reason: describe(loaded));
        final Map<String, Object?> app = loaded
            .unwrap()
            .rawSlice('app')
            .unwrap();
        expect(app['name'], 'development');
        expect(app['tags'], <String>['development']);
        expect(app['retries'], 2, reason: 'the landscape layer still applies');
      },
    );

    test('indexed defines build the list that replaces the YAML one', () async {
      // Arrange
      final Map<String, Object?> vector = _vector(
        fixture,
        'layeringAndIndexedList',
      );
      final Map<String, String> defines = _defines(vector);

      // Act
      final Result<DieneConfig> loaded = await _load(
        vector,
        overlayKey: 'landscapeYaml',
      );

      // Assert
      expect(
        defines.keys,
        containsAll(<String>['ACME_APP__TAGS__0', 'ACME_APP__TAGS__1']),
        reason: 'the vector must exercise indexed keys',
      );
      expect(loaded.unwrap().rawSlice('app').unwrap()['tags'], <String>[
        'first',
        'second',
      ]);
    });
  });

  group('C0 §3 blank is unset', () {
    test('a blank define does not erase the base value', () async {
      // Arrange
      final Map<String, Object?> vector = _vector(fixture, 'blankIsUnset');

      // Act
      final Result<DieneConfig> loaded = await _load(vector);

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      expect(loaded.unwrap().rawSlice('app').unwrap(), vector['expected']);
    });

    test('the blank define layer contributes nothing at all', () async {
      // Arrange
      final Map<String, Object?> vector = _vector(fixture, 'blankIsUnset');
      final DartDefineOverrides overrides = DartDefineOverrides(
        prefix: vector['prefix']! as String,
        values: _defines(vector),
      );

      // Act
      final Result<Object?> layer = overrides.layer();

      // Assert
      expect(layer, isOk, reason: describe(layer));
      expect(layer.unwrap()! as Map<String, Object?>, isEmpty);
    });
  });

  group('C0 §3 case-insensitive key matching', () {
    test('every spelling variant lands on the base layer key', () async {
      // Arrange
      final Map<String, Object?> vector = _vector(
        fixture,
        'caseInsensitiveKeyMatching',
      );
      final List<Object?> variants = vector['variants']! as List<Object?>;
      expect(variants, hasLength(3), reason: 'expected snake, kebab, pascal');

      for (final Object? raw in variants) {
        final Map<String, Object?> variant = (raw! as Map<Object?, Object?>)
            .cast<String, Object?>();
        final String defineKey = variant['defineKey']! as String;
        final String expectedValue = variant['expectedValue']! as String;

        // Act
        final Result<DieneConfig> loaded = await ConfigLoader(
          base: YamlConfigSource.string(vector['baseYaml']! as String),
          dartDefines: DartDefineOverrides(
            prefix: vector['prefix']! as String,
            values: <String, String>{defineKey: expectedValue},
          ),
          schema: ConfigSchema(
            blocks: <ConfigBlockSchema>[
              ConfigBlock<String>(
                key: 'app-settings',
                decode: (Map<String, Object?> values) =>
                    values['displayName']! as String,
              ),
            ],
          ),
        ).load();

        // Assert
        expect(loaded, isOk, reason: '$defineKey: ${describe(loaded)}');
        final DieneConfig config = loaded.unwrap();
        expect(
          config.raw.keys,
          <String>['app-settings'],
          reason: '$defineKey introduced a duplicate root spelling',
        );
        final Map<String, Object?> settings = config
            .rawSlice('app-settings')
            .unwrap();
        expect(
          settings.keys,
          <String>['displayName'],
          reason: "$defineKey did not land on the base layer's spelling",
        );
        expect(settings['displayName'], expectedValue);
      }
    });
  });

  group('C0 §3 no JSON, no comma encoding', () {
    test('neither encoding is ever decoded into a list', () async {
      // Arrange
      final Map<String, Object?> vector = _vector(fixture, 'noJsonNoComma');
      final List<Object?> rejected = vector['rejected']! as List<Object?>;
      expect(rejected, hasLength(2), reason: 'expected JSON and comma cases');

      // The claim under test is about the MERGE — that no list is ever
      // materialised from a JSON or comma string — so the block accepts `tags`
      // whatever its type and the assertion inspects it. A strict decoder would
      // reject the string and the suite would go green on validation instead
      // of on the rule it is meant to bind.
      final ConfigSchema permissive = ConfigSchema(
        blocks: <ConfigBlockSchema>[
          ConfigBlock<Object?>(
            key: 'app',
            decode: (Map<String, Object?> values) => values['tags'],
          ),
        ],
      );

      for (final Object? raw in rejected) {
        final Map<String, Object?> entry = (raw! as Map<Object?, Object?>)
            .cast<String, Object?>();

        // Act
        final Result<DieneConfig> loaded = await ConfigLoader(
          base: YamlConfigSource.string(entry['baseYaml']! as String),
          dartDefines: DartDefineOverrides(
            prefix: entry['prefix']! as String,
            values: _defines(entry),
          ),
          schema: permissive,
        ).load();

        // Assert
        expect(loaded, isOk, reason: '${entry['name']}: ${describe(loaded)}');
        final Object? tags = loaded.unwrap().rawSlice('app').unwrap()['tags'];
        expect(
          tags,
          isA<String>(),
          reason: '${entry['name']} encoding was decoded into a collection',
        );
        expect(tags, _defines(entry).values.single);
      }
    });

    test('a strict decoder still SEES the string, and says so', () async {
      // The complementary half: an application whose block expects a list gets
      // a validation failure naming the type mismatch, rather than a silently
      // decoded list. That is the rule's practical consequence.
      // Arrange
      final Map<String, Object?> vector = _vector(fixture, 'noJsonNoComma');
      final Map<String, Object?> entry =
          ((vector['rejected']! as List<Object?>).first!
                  as Map<Object?, Object?>)
              .cast<String, Object?>();

      // Act
      final Result<DieneConfig> loaded = await ConfigLoader(
        base: YamlConfigSource.string(entry['baseYaml']! as String),
        dartDefines: DartDefineOverrides(
          prefix: entry['prefix']! as String,
          values: _defines(entry),
        ),
        schema: appSchema(),
      ).load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      expect(
        loaded.unwrapErr().data['code'],
        ConfigProblemCode.schemaInvalid.wireId,
      );
    });
  });

  group('C0 §3 final-layer validation', () {
    test('an invalid FINAL tree is rejected', () async {
      // Arrange
      final Map<String, Object?> vector = _vector(
        fixture,
        'finalLayerValidation',
      );
      final Map<String, Object?> invalid =
          (vector['invalid']! as Map<Object?, Object?>).cast<String, Object?>();

      // Act
      final Result<DieneConfig> loaded = await _load(invalid);

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      final Problem problem = loaded.unwrapErr();
      expect(problem.data['code'], ConfigProblemCode.schemaInvalid.wireId);
      expect(
        (problem.data['errors']! as List<Object?>).join(),
        contains('retries'),
      );
    });

    test('the SAME tree is accepted once a later layer repairs it', () async {
      // Validation is final-layer-only, so the identical base becomes valid
      // when a define fixes it. This is the half of the rule an
      // "invalid input is rejected" test alone cannot prove.
      // Arrange
      final Map<String, Object?> vector = _vector(
        fixture,
        'finalLayerValidation',
      );
      final Map<String, Object?> invalid =
          (vector['invalid']! as Map<Object?, Object?>).cast<String, Object?>();

      // Act
      final Result<DieneConfig> loaded = await _load(
        invalid,
        defines: <String, String>{
          '${invalid['prefix']}APP__RETRIES': '5',
          '${invalid['prefix']}APP__TAGS__0': 'repaired',
        },
      );

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      final Map<String, Object?> app = loaded.unwrap().rawSlice('app').unwrap();
      expect(app['retries'], 5);
      expect(app['tags'], <String>['repaired']);
    });

    test('validation runs exactly once, on the merged tree', () async {
      // A loader validating each layer would reject the invalid base before
      // the define could repair it — the previous test's Ok is the proof, and
      // this counts the decoder calls to say so directly.
      // Arrange
      final Map<String, Object?> vector = _vector(
        fixture,
        'finalLayerValidation',
      );
      final Map<String, Object?> invalid =
          (vector['invalid']! as Map<Object?, Object?>).cast<String, Object?>();
      int decodeCalls = 0;
      final ConfigBlock<int> countingBlock = ConfigBlock<int>(
        key: 'app',
        decode: (Map<String, Object?> values) {
          decodeCalls += 1;
          return values['retries']! as int;
        },
      );

      // Act
      final Result<DieneConfig> loaded = await ConfigLoader(
        base: YamlConfigSource.string(invalid['baseYaml']! as String),
        overlay: YamlConfigSource.string('app:\n  retries: 1\n'),
        developmentOverride: YamlConfigSource.string('app:\n  retries: 2\n'),
        dartDefines: DartDefineOverrides(
          prefix: invalid['prefix']! as String,
          values: <String, String>{'${invalid['prefix']}APP__RETRIES': '3'},
        ),
        schema: ConfigSchema(blocks: <ConfigBlockSchema>[countingBlock]),
      ).load();

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      expect(
        decodeCalls,
        1,
        reason: 'four layers were loaded but validation must run ONCE',
      );
      expect(loaded.unwrap().slice(countingBlock), 3);
    });
  });
}

Map<String, Object?> _vector(Map<String, Object?> fixture, String name) =>
    (fixture[name]! as Map<Object?, Object?>).cast<String, Object?>();

/// Decodes [text] as a JSON object, naming [what] if it is not one.
Map<String, Object?> _object(String text, String what) {
  final Object? decoded = jsonDecode(text);
  if (decoded is! Map<Object?, Object?>) {
    throw StateError('$what is not a JSON object');
  }
  return decoded.cast<String, Object?>();
}

/// A deep, independently mutable copy, so a forgery cannot disturb the fixture.
Object? _clone(Object? value) => jsonDecode(jsonEncode(value));

Map<String, String> _defines(Map<String, Object?> vector) =>
    (vector['defines']! as Map<Object?, Object?>).cast<String, String>();

/// Runs one fixture vector through the REAL loader.
Future<Result<DieneConfig>> _load(
  Map<String, Object?> vector, {
  String? overlayKey,
  String? developmentKey,
  Map<String, String>? defines,
}) {
  String? layer(String? key) => key == null ? null : vector[key] as String?;

  final String? overlay = layer(overlayKey);
  final String? development = layer(developmentKey);
  return ConfigLoader(
    base: YamlConfigSource.string(
      vector['baseYaml']! as String,
      name: 'base.yaml',
    ),
    overlay: overlay == null
        ? null
        : YamlConfigSource.string(overlay, name: 'overlay.yaml'),
    developmentOverride: development == null
        ? null
        : YamlConfigSource.string(development, name: 'development.yaml'),
    dartDefines: DartDefineOverrides(
      prefix: vector['prefix']! as String,
      values: defines ?? _defines(vector),
    ),
    schema: appSchema(),
  ).load();
}
