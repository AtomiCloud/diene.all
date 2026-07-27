// C0 CONFORMANCE for the auth-engine `identity` domain (§7 app-handoff, §8
// onboarding multi-backend, §10 edge docs, §12 token lifetimes, §13 home claim).
//
// BOUND TO THE AUTHORITATIVE FROZEN FIXTURE. Every vector below is READ from
// `test/fixtures/c0/identity.json`, which `tool/gen_c0_projection.dart` projects
// from `contracts/c0/cases/identity.json` (releaseId `c0-fixtures-r2`,
// contractVersion 2). Nothing here is a hand-copied literal, so a contract
// change lands as a red test rather than as silent drift.
//
// THIS SUPERSEDES THE PREVIOUS HEADER ON THIS FILE, quoted verbatim so the
// record of why it existed survives the fix:
//
//   "AUTHORITATIVE-FIXTURE BINDING IS INTEGRATION/REDESIGN-HELD (RB-315-class):
//    no source-owned, versioned C0 conformance fixture exists yet for these
//    sections — `goals/c0-contracts.md` ships contract PROSE, not a
//    machine-readable fixture artifact ... When the conductor materializes the
//    versioned source-owned C0 fixture set, these vectors must be re-pointed at
//    it and its version/provenance recorded."
//
// That was TRUE when written, on the pre-transplant flutter-base parent. It is
// FALSE now, and the hold is DISCHARGED on its own stated terms: the R-E19a
// transplant onto the dart-lib parent brought `contracts/c0/` (17 files,
// byte-identical to the four accepted dart siblings), whose `cases/identity.json`
// IS the versioned source-owned fixture, with prose provenance under
// `contracts/c0/provenance/{app-handoff,edge-docs,home-claim,onboarding-claim,
// token-lifetimes}.md`. Version and provenance are recorded in the projection's
// `$generated` block and asserted below.
//
// Dart is EXEMPT from the C0 otel config block (frontend-only; telemetry rides
// Faro through flutter-base).
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads the projected fixture and PROVES it is the bytes the manifest records.
/// A tampered fixture must fail here — this is the assertion the
/// `c0-fixture-harness` probe sabotages to prove the gate is real.
Map<String, Object?> _loadFixture() {
  final File fixture = File('test/fixtures/c0/identity.json');
  final File sums = File('test/fixtures/c0/SHA256SUMS');
  if (!fixture.existsSync()) {
    throw StateError('C0 fixture missing: ${fixture.path}');
  }
  if (!sums.existsSync()) {
    throw StateError('C0 fixture manifest missing: ${sums.path}');
  }

  final String raw = fixture.readAsStringSync();
  final String actual = sha256.convert(utf8.encode(raw)).toString();

  // Parse the manifest as a STRUCTURED two-field record rather than substring
  // matching it: "the recorded digest equals the computed one" must be answered
  // on a value, and "I could not find a digest" must NOT read the same as "the
  // digest matched".
  final List<String> rows = sums
      .readAsStringSync()
      .split('\n')
      .where((String l) => l.trim().isNotEmpty)
      .toList();
  final List<String> recorded = rows
      .map((String l) => l.trim().split(RegExp(r'\s+')))
      .where((List<String> p) => p.length == 2 && p[1] == 'identity.json')
      .map((List<String> p) => p[0])
      .toList();
  if (recorded.isEmpty) {
    throw StateError(
      'C0 fixture manifest has no identity.json row (${rows.length} row(s) '
      'present) — refusing to report conformance without a digest to check',
    );
  }
  if (recorded.single != actual) {
    throw StateError(
      'C0 fixture digest mismatch for identity.json:\n'
      '  recorded: ${recorded.single}\n'
      '  computed: $actual',
    );
  }

  return (jsonDecode(raw) as Map<Object?, Object?>).cast<String, Object?>();
}

Map<String, Object?> _obj(Object? node) =>
    (node! as Map<Object?, Object?>).cast<String, Object?>();

List<Map<String, Object?>> _objs(Object? node) =>
    (node! as List<Object?>).map(_obj).toList();

void main() {
  final Map<String, Object?> fixture = _loadFixture();

  test('the fixture is the frozen c0-fixtures-r2 identity release', () {
    final Map<String, Object?> gen = _obj(fixture[r'$generated']);
    expect(gen['domain'], 'identity');
    expect(gen['releaseId'], 'c0-fixtures-r2');
    expect(gen['sourceCase'], 'contracts/c0/cases/identity.json');
    expect(gen['releaseDigest'], isA<String>());
    expect(
      gen['c0Sections'],
      containsAll(<String>[
        '§7 App-handoff contract',
        '§8 Onboarding contract (multi-backend)',
        '§10 Edge docs — three-doc model',
        '§12 Token lifetimes',
        '§13 Home claim + pre-onboarding',
      ]),
    );
  });

  group('C0 §12 token lifetimes', () {
    test('all four normative values match the fixture', () {
      final Map<String, Object?> t = _obj(fixture['tokenLifetimes']);
      expect(
        TokenLifetimes.access,
        Duration(minutes: t['accessMinutes']! as int),
      );
      expect(TokenLifetimes.refresh, Duration(days: t['refreshDays']! as int));
      expect(TokenLifetimes.refreshRotating, t['refreshRotating']);
      expect(TokenLifetimes.remintOnOpen, t['remintOnOpen']);
    });
  });

  group('C0 §13 home claim', () {
    test('claim name matches the fixture', () {
      expect(Claims.homeLandscape, _obj(fixture['homeClaim'])['claimName']);
    });

    test('every PRESENT vector yields its expected landscape', () {
      final Map<String, Object?> vectors = _obj(
        _obj(fixture['homeClaim'])['vectors'],
      );
      final List<Map<String, Object?>> present = _objs(vectors['present']);
      expect(present, isNotEmpty, reason: 'fixture must carry present vectors');
      for (final Map<String, Object?> v in present) {
        expect(
          Claims.home(_obj(v['claims'])),
          v['expected'],
          reason: 'home claim vector "${v['name']}"',
        );
      }
    });

    test('every ABSENT vector reads as null (blank/non-string/missing)', () {
      final Map<String, Object?> vectors = _obj(
        _obj(fixture['homeClaim'])['vectors'],
      );
      final List<Map<String, Object?>> absent = _objs(vectors['absent']);
      expect(absent, isNotEmpty);
      for (final Map<String, Object?> v in absent) {
        expect(
          Claims.home(_obj(v['claims'])),
          isNull,
          reason: 'home claim vector "${v['name']}" must read as absent',
        );
      }
    });
  });

  group('C0 §8 onboarding claim (multi-backend)', () {
    test('every PRESENT vector produces the expected key and reads true', () {
      final Map<String, Object?> c = _obj(fixture['onboardingClaim']);
      final List<Map<String, Object?>> present = _objs(
        _obj(c['vectors'])['present'],
      );
      expect(present, isNotEmpty);
      for (final Map<String, Object?> v in present) {
        final String platform = v['platform']! as String;
        final String service = v['service']! as String;
        expect(
          Claims.registrationKey(platform: platform, service: service),
          v['expectedKey'],
          reason: 'onboarding key vector "${v['name']}"',
        );
        expect(
          Claims.hasRegistration(
            _obj(v['claims']),
            platform: platform,
            service: service,
          ),
          isTrue,
          reason: 'onboarding present vector "${v['name']}"',
        );
      }
    });

    test('every ABSENT vector is rejected — only the string "true" counts', () {
      final Map<String, Object?> c = _obj(fixture['onboardingClaim']);
      expect(c['registeredValue'], 'true');
      final List<Map<String, Object?>> absent = _objs(
        _obj(c['vectors'])['absent'],
      );
      expect(absent, isNotEmpty);
      for (final Map<String, Object?> v in absent) {
        expect(
          Claims.hasRegistration(
            _obj(v['claims']),
            platform: v['platform']! as String,
            service: v['service']! as String,
          ),
          isFalse,
          reason: 'onboarding absent vector "${v['name']}" must not register',
        );
      }
    });
  });

  group('C0 §8/S7 resource audience', () {
    test('every VALID vector builds the fixture audience and map key', () {
      final List<Map<String, Object?>> valid = _objs(
        _obj(_obj(fixture['resourceAudience'])['vectors'])['valid'],
      );
      expect(valid, isNotEmpty);
      for (final Map<String, Object?> v in valid) {
        final ResourceKey key = ResourceKey(
          platform: v['platform']! as String,
          landscape: v['landscape']! as String,
          service: v['service']! as String,
          resourceName: v['resourceName']! as String,
        );
        expect(
          key.audience.toString(),
          v['expectedAudience'],
          reason: 'audience vector "${v['name']}"',
        );
        expect(
          key.mapKey,
          v['expectedMapKey'],
          reason: 'map-key vector "${v['name']}"',
        );
      }
    });

    test('every INVALID label vector is rejected', () {
      final List<Map<String, Object?>> invalid = _objs(
        _obj(_obj(fixture['resourceAudience'])['vectors'])['invalid'],
      );
      expect(invalid, isNotEmpty);
      for (final Map<String, Object?> v in invalid) {
        expect(
          () => ResourceKey(
            platform: v['platform']! as String,
            landscape: v['landscape']! as String,
            service: v['service']! as String,
            resourceName: v['resourceName']! as String,
          ),
          throwsFormatException,
          reason: 'invalid label vector "${v['name']}" must be rejected',
        );
      }
    });
  });

  group('C0 §7 app-handoff carrier', () {
    test('fixed constants match the fixture', () {
      final Map<String, Object?> a = _obj(fixture['appHandoff']);
      expect(
        AppHandoffConstants.nonceTtl,
        Duration(minutes: a['nonceTtlMinutes']! as int),
      );
      expect(
        AppHandoffConstants.oneTimeTokenExpiresInSeconds,
        a['oneTimeTokenExpiresInSeconds'],
      );
      expect(AppHandoffConstants.defaultMount, a['defaultMount']);
    });

    test('every VALID carrier vector parses to its expected nonce', () {
      final Map<String, Object?> a = _obj(fixture['appHandoff']);
      final List<Map<String, Object?>> valid = _objs(
        _obj(a['carriers'])['valid'],
      );
      expect(valid, isNotEmpty);
      int checked = 0;
      for (final Map<String, Object?> v in valid) {
        final String expectedNonce = v['nonce']! as String;
        // A vector carries at least one transport: canonical text, an Android
        // Install Referrer payload, or clipboard content.
        if (v['androidReferrer'] != null) {
          expect(
            AppHandoffCarrier.parseAndroidReferrer(
              v['androidReferrer']! as String,
            )?.nonce,
            expectedNonce,
            reason: 'android carrier vector "${v['name']}"',
          );
          checked++;
        }
        if (v['clipboard'] != null) {
          expect(
            AppHandoffCarrier.parseClipboard(v['clipboard']! as String)?.nonce,
            expectedNonce,
            reason: 'clipboard carrier vector "${v['name']}"',
          );
          checked++;
        }
        if (v['text'] != null) {
          final AppHandoffCarrier? c = AppHandoffCarrier.parseCanonical(
            v['text']! as String,
          );
          expect(
            c?.nonce,
            expectedNonce,
            reason: 'canonical carrier vector "${v['name']}"',
          );
          expect(c?.canonicalText, v['text']);
          checked++;
        }
      }
      // Refuse a vacuous pass: every vector must have exercised a transport, so
      // a fixture entry with no recognised transport key fails loudly instead of
      // being skipped in silence.
      expect(
        checked,
        greaterThanOrEqualTo(valid.length),
        reason: 'every valid vector must exercise at least one transport',
      );
    });

    test('every INVALID carrier vector is rejected', () {
      final Map<String, Object?> a = _obj(fixture['appHandoff']);
      final List<Map<String, Object?>> invalid = _objs(
        _obj(a['carriers'])['invalid'],
      );
      expect(invalid, isNotEmpty);
      int checked = 0;
      for (final Map<String, Object?> v in invalid) {
        if (v['androidReferrer'] != null) {
          expect(
            AppHandoffCarrier.parseAndroidReferrer(
              v['androidReferrer']! as String,
            ),
            isNull,
            reason: 'android invalid vector "${v['name']}"',
          );
          checked++;
        }
        if (v['text'] != null) {
          expect(
            AppHandoffCarrier.parseCanonical(v['text']! as String),
            isNull,
            reason: 'canonical invalid vector "${v['name']}"',
          );
          checked++;
        }
      }
      expect(checked, greaterThanOrEqualTo(invalid.length));
    });

    test('the nonce shape matches the fixture pattern and length', () {
      final Map<String, Object?> a = _obj(fixture['appHandoff']);
      final int length = a['nonceLength']! as int;
      final RegExp pattern = RegExp(a['noncePattern']! as String);
      final String prefix = a['carrierPrefix']! as String;
      final String nonce = 'A' * length;
      expect(pattern.hasMatch(nonce), isTrue);
      final AppHandoffCarrier? parsed = AppHandoffCarrier.parseCanonical(
        '$prefix$nonce',
      );
      expect(parsed, isNotNull);
      expect(parsed!.nonce.length, length);
      // One shorter and one longer must BOTH be refused, so the length bound is
      // proven exact rather than merely satisfied from one side.
      expect(
        AppHandoffCarrier.parseCanonical('$prefix${'A' * (length - 1)}'),
        isNull,
      );
      expect(
        AppHandoffCarrier.parseCanonical('$prefix${'A' * (length + 1)}'),
        isNull,
      );
    });

    test('the generic expiry problem is a NO-ORACLE 410 from the fixture', () {
      final Map<String, Object?> expected = _obj(
        _obj(fixture['appHandoff'])['genericExpiryProblem'],
      );
      final Problem problem = appHandoffExpired();
      expect(problem.status, expected['status']);
      expect(problem.title, expected['title']);
      expect(problem.detail, expected['detail']);
      expect(problem.data, isEmpty, reason: 'must leak no distinguishing data');

      // DOCUMENTED DELTA. The fixture identifies this problem by `id`
      // ("AppHandoffExpired"), not by a full type URI, because the C0 §2 type
      // URI is minted from an ErrorPortal (scheme/host/landscape/platform/
      // service/module) plus version and id — per-landscape SERVER context that
      // a client library provably does not have. The dotnet-api that HOSTS
      // mint/redeem emits the C0 URI; this client emits a stable local URN for
      // its own transport-failure fallback. What is asserted here is that the
      // URN's final segment is the fixture id in kebab form, so the two cannot
      // drift apart unnoticed.
      final String id = expected['id']! as String;
      final String kebab = id
          .replaceAllMapped(
            RegExp('(?<=[a-z0-9])[A-Z]'),
            (Match m) => '-${m[0]}',
          )
          .toLowerCase();
      expect(problem.type, endsWith(kebab));
    });

    test('mint and redeem routes match the fixture templates', () {
      final Map<String, Object?> a = _obj(fixture['appHandoff']);
      final Map<String, Object?> mint = _obj(a['mintRoute']);
      final Map<String, Object?> redeem = _obj(a['redeemRoute']);
      const String mount = AppHandoffConstants.defaultMount;
      expect(mint['method'], 'POST');
      expect((mint['path']! as String).replaceAll('{mount}', mount), mount);
      expect(redeem['method'], 'POST');
      expect(
        (redeem['path']! as String).replaceAll('{mount}', mount),
        '$mount/redeem',
      );
      expect(
        a['redeemSuccessKeys'],
        containsAll(<String>['token', 'email', 'expiresIn']),
      );
    });
  });

  group('C0 §10 Doc B — landscape selector', () {
    test('every VALID doc parses, names + metadata only', () {
      final List<Map<String, Object?>> valid = _objs(
        _obj(_obj(fixture['docB'])['vectors'])['valid'],
      );
      expect(valid, isNotEmpty);
      for (final Map<String, Object?> v in valid) {
        final LandscapeSelectorDoc doc = LandscapeSelectorDoc.fromJson(
          _obj(v['doc']),
        );
        expect(
          doc.landscapes,
          isNotEmpty,
          reason: 'doc B vector "${v['name']}"',
        );
        for (final LandscapeEntry e in doc.landscapes) {
          expect(e.name, isNotEmpty);
        }
      }
    });

    test('every INVALID doc is untrusted as a whole', () {
      final List<Map<String, Object?>> invalid = _objs(
        _obj(_obj(fixture['docB'])['vectors'])['invalid'],
      );
      expect(invalid, isNotEmpty);
      for (final Map<String, Object?> v in invalid) {
        expect(
          () => LandscapeSelectorDoc.fromJson(_obj(v['doc'])),
          throwsA(anyOf(isA<FormatException>(), isA<TypeError>())),
          reason: 'doc B invalid vector "${v['name']}" must be rejected',
        );
      }
    });

    test('the required key vocabulary matches the fixture', () {
      final Map<String, Object?> d = _obj(fixture['docB']);
      expect(
        d['requiredKeys'],
        containsAll(<String>['landscapes', 'platform', 'tier']),
      );
      expect(d['requiredEntryKeys'], containsAll(<String>['name', 'region']));
    });
  });
}
