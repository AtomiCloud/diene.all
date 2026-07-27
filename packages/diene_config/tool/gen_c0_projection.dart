// Generates the C0 §3 config-precedence projection for `diene_config`.
//
// This package implements the FULL §3 contract — the layered ladder, the
// case-insensitive key matching, `__`-indexed lists, blank-is-unset, the
// no-JSON/no-comma rule, AND the final-layer validation rule that
// `diene_core_utils` deliberately leaves to its consumer — so all FIVE vectors
// in the frozen release `contracts/c0/cases/config.json` (releaseId
// `c0-fixtures-r2`) are projected here.
//
// That is the one difference from the core-utils generator, which projects only
// the four mechanics it implements: `finalLayerValidation` belongs to whoever
// owns schema validation, and that is this package.
//
// The projection is AUTHENTICATED to the frozen release, not copied from it.
// Carrying a `releaseDigest`-shaped field would prove nothing: an edited
// normative case could be regenerated into a fixture that is perfectly
// self-consistent — new vectors, new local checksum, old digest string — and
// every package test would stay green. So before a byte is written this tool
//
//   1. re-renders `contracts/c0/RELEASE.json` in the compact-canonical form the
//      release recipe hashes, and refuses to continue unless the committed
//      bytes match;
//   2. recomputes the complete-release digest over the domain separator, the
//      manifest WITHOUT its own `releaseDigest`, and the exact committed
//      `contracts/c0/SHA256SUMS` bytes, and requires it to equal both the
//      digest the manifest records and the digest pinned in
//      `lib/src/c0_config_contract.dart`;
//   3. requires `contracts/c0/SHA256SUMS` to record the hash of the exact
//      normative case bytes it is about to project; and
//   4. requires those case bytes to be pretty-canonical and to hold exactly the
//      projected vectors, so the same chain can be re-derived from the
//      projection alone.
//
// It then embeds the ledger bytes and the manifest witness in the fixture,
// which is what lets `test/conformance/c0_config_test.dart` re-run steps 2-4
// against the vectors it actually drives. An edited case therefore only stays
// green if the ACCEPTED release identity is changed too — in the library pin
// and in `scripts/validate/c0-release.sh`, which pins the same digest and the
// release commit independently.
//
// Usage from the member directory:
//   dart run tool/gen_c0_projection.dart
//   dart run tool/gen_c0_projection.dart --check

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diene_config/c0_config.dart';

/// Root of the neutral C0 release, relative to the repository root.
const String c0ContractsRoot = 'contracts/c0';

/// The release manifest, relative to the repository root.
const String c0ReleaseManifestPath = '$c0ContractsRoot/RELEASE.json';

/// The release-wide SHA-256 ledger, relative to the repository root.
const String c0ReleaseLedgerPath = '$c0ContractsRoot/SHA256SUMS';

/// Domain separator of the complete-release digest recipe.
///
/// Recorded in `contracts/c0/README.md`: the digest is SHA-256 over this line,
/// the compact-canonical manifest without its `releaseDigest`, and the exact
/// committed `SHA256SUMS` bytes.
const String c0ReleaseDigestDomain = 'atomicloud.diene.c0-fixtures.release.v1';

const String _fixturePath = 'test/fixtures/c0/config.json';
const String _checksumPath = 'test/fixtures/c0/SHA256SUMS';

/// Raised when the release bytes do not authenticate. Every path fails closed.
final class C0ReleaseAuthenticationFailure implements Exception {
  /// Creates a failure describing why authentication was refused.
  const C0ReleaseAuthenticationFailure(this.reason);

  /// Why the bytes were refused.
  final String reason;

  @override
  String toString() => 'C0 release authentication failed: $reason';
}

/// The authenticated inputs a projection may be built from.
final class C0AuthenticatedRelease {
  /// Records the outcome of a successful authentication.
  const C0AuthenticatedRelease({
    required this.releaseDigest,
    required this.domain,
    required this.c0Sections,
    required this.cases,
    required this.caseSha256,
    required this.ledgerEntry,
  });

  /// The recomputed complete-release digest, equal to the accepted pin.
  final String releaseDigest;

  /// Domain of the normative case file, e.g. `config`.
  final String domain;

  /// The binding C0 sections, as recorded in the normative case file.
  final List<Object?> c0Sections;

  /// The normative vectors, keyed by case name.
  final Map<String, Object?> cases;

  /// SHA-256 of the exact normative case bytes, as recorded in the ledger.
  final String caseSha256;

  /// Ledger path of the normative case, relative to [c0ContractsRoot].
  final String ledgerEntry;
}

/// SHA-256 of [text] as UTF-8, in lowercase hex.
String sha256HexOf(String text) => sha256.convert(utf8.encode(text)).toString();

/// The complete-release digest of a manifest witness and ledger.
///
/// [manifestWithoutDigest] is the compact-canonical manifest with its
/// `releaseDigest` removed and no trailing newline; [ledgerText] is the exact
/// committed ledger, trailing newline included.
String c0ReleaseDigestOf({
  required String manifestWithoutDigest,
  required String ledgerText,
}) =>
    sha256HexOf('$c0ReleaseDigestDomain\n$manifestWithoutDigest\n$ledgerText');

/// Renders [value] with recursively sorted keys and no extra whitespace.
String canonicalCompactJson(Object? value) => jsonEncode(_sorted(value));

/// Renders [value] with recursively sorted keys and two-space indentation.
String canonicalPrettyJson(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(_sorted(value));

/// Re-renders the normative case file bytes from projected parts.
///
/// The frozen case files are pretty-canonical with one trailing newline, so a
/// projection that carries every vector can reproduce their exact bytes — which
/// is what lets the conformance gate re-check them against the release ledger.
String renderNormativeCaseBytes({
  required String domain,
  required Object? c0Sections,
  required Map<String, Object?> cases,
}) {
  final Map<String, Object?> caseFile = <String, Object?>{
    'c0Sections': c0Sections,
    'cases': cases,
    'domain': domain,
  };
  return '${canonicalPrettyJson(caseFile)}\n';
}

/// Parses a `sha256sum` ledger under the strict release grammar.
///
/// Throws [C0ReleaseAuthenticationFailure] on a malformed, unterminated, empty
/// or duplicated ledger rather than skipping the offending line: a ledger that
/// silently loses entries authenticates nothing.
Map<String, String> parseC0Ledger(String ledgerText) {
  if (ledgerText.isEmpty || !ledgerText.endsWith('\n')) {
    throw const C0ReleaseAuthenticationFailure(
      'the release ledger is empty or not newline-terminated',
    );
  }
  final RegExp grammar = RegExp(r'^([0-9a-f]{64})  (\S.*)$');
  final Map<String, String> entries = <String, String>{};
  final List<String> lines = ledgerText
      .substring(0, ledgerText.length - 1)
      .split('\n');
  for (final String line in lines) {
    final RegExpMatch? match = grammar.firstMatch(line);
    if (match == null) {
      throw C0ReleaseAuthenticationFailure(
        'the release ledger has a malformed line: "$line"',
      );
    }
    final String path = match.group(2)!;
    if (entries.containsKey(path)) {
      throw C0ReleaseAuthenticationFailure(
        'the release ledger records $path twice',
      );
    }
    entries[path] = match.group(1)!;
  }
  return entries;
}

/// Authenticates frozen release bytes against an accepted release pin.
///
/// Returns the vectors a projection may be built from, or throws
/// [C0ReleaseAuthenticationFailure]. The chain is: the case bytes hash to the
/// entry the ledger records, the ledger and manifest witness hash to the
/// complete-release digest, and that digest is the one [pin] accepts. Nothing
/// here trusts a copied metadata field.
C0AuthenticatedRelease authenticateC0Release({
  required String manifestWithoutDigest,
  required String ledgerText,
  required String caseText,
  required C0ConfigProvenance pin,
  required List<String> projectedCases,
}) {
  // 1. The witness must be exactly the bytes the digest recipe hashes, and must
  //    not carry the digest it is supposed to prove.
  final Map<String, Object?> manifest = _decodeObject(
    manifestWithoutDigest,
    'release manifest witness',
  );
  if (manifest.containsKey('releaseDigest')) {
    throw const C0ReleaseAuthenticationFailure(
      'the manifest witness still carries releaseDigest, so it cannot be the '
      'preimage of the digest it claims',
    );
  }
  if (canonicalCompactJson(manifest) != manifestWithoutDigest) {
    throw const C0ReleaseAuthenticationFailure(
      'the manifest witness is not compact-canonical, so its digest is not the '
      'release digest',
    );
  }

  // 2. Re-derive the complete-release digest and require the accepted identity.
  final String digest = c0ReleaseDigestOf(
    manifestWithoutDigest: manifestWithoutDigest,
    ledgerText: ledgerText,
  );
  if (digest != pin.releaseDigest) {
    throw C0ReleaseAuthenticationFailure(
      'the release bytes hash to $digest, but the accepted release '
      '${pin.releaseId} is ${pin.releaseDigest}',
    );
  }
  if (pin.releaseId != 'c0-fixtures-r${pin.contractVersion}') {
    throw C0ReleaseAuthenticationFailure(
      'the accepted release id ${pin.releaseId} does not match contract '
      'version ${pin.contractVersion}',
    );
  }
  if (manifest['releaseId'] != pin.releaseId) {
    throw C0ReleaseAuthenticationFailure(
      'the manifest identifies release ${manifest['releaseId']}, not the '
      'accepted ${pin.releaseId}',
    );
  }
  if (manifest['contractVersion'] != pin.contractVersion) {
    throw C0ReleaseAuthenticationFailure(
      'the manifest declares contract version ${manifest['contractVersion']}, '
      'not the accepted ${pin.contractVersion}',
    );
  }

  // 3. The ledger must authenticate the exact case bytes being projected.
  final String ledgerEntry = _ledgerEntryFor(pin.sourceCase);
  final String? recorded = parseC0Ledger(ledgerText)[ledgerEntry];
  if (recorded == null) {
    throw C0ReleaseAuthenticationFailure(
      'the release ledger has no entry for $ledgerEntry',
    );
  }
  final String actual = sha256HexOf(caseText);
  if (actual != recorded) {
    throw C0ReleaseAuthenticationFailure(
      'the normative case bytes hash to $actual, but $c0ReleaseLedgerPath '
      'records $recorded for $ledgerEntry',
    );
  }
  final Object? domains = manifest['domains'];
  final String domain = _domainOf(pin.sourceCase);
  if (domains is! List<Object?> || !domains.contains(domain)) {
    throw C0ReleaseAuthenticationFailure(
      'the manifest does not publish a $domain domain',
    );
  }

  // 4. The case bytes must be pretty-canonical and must hold exactly the
  //    projected vectors, or the projection would not be a lossless,
  //    re-renderable image of the authenticated bytes.
  final Map<String, Object?> caseFile = _decodeObject(caseText, 'case file');
  if ('${canonicalPrettyJson(caseFile)}\n' != caseText) {
    throw const C0ReleaseAuthenticationFailure(
      'the normative case bytes are not pretty-canonical, so a projection '
      'cannot reproduce them',
    );
  }
  _expectKeys(caseFile, <String>[
    'c0Sections',
    'cases',
    'domain',
  ], 'the normative case file');
  if (caseFile['domain'] != domain) {
    throw C0ReleaseAuthenticationFailure(
      'the normative case file declares domain ${caseFile['domain']}, not '
      '$domain',
    );
  }
  final List<Object?> c0Sections = _expectList(
    caseFile['c0Sections'],
    'c0Sections',
  );
  if (canonicalCompactJson(c0Sections) !=
      canonicalCompactJson(pin.c0Sections)) {
    throw C0ReleaseAuthenticationFailure(
      'the normative case file binds $c0Sections, not the accepted '
      '${pin.c0Sections}',
    );
  }
  final Map<String, Object?> cases = _expectObject(caseFile['cases'], 'cases');
  _expectKeys(cases, projectedCases, 'the normative vectors');

  return C0AuthenticatedRelease(
    releaseDigest: digest,
    domain: domain,
    c0Sections: c0Sections,
    cases: cases,
    caseSha256: actual,
    ledgerEntry: ledgerEntry,
  );
}

void main(List<String> args) {
  final bool check = args.contains('--check');
  final Directory packageRoot = File.fromUri(Platform.script).parent.parent;
  final Directory repositoryRoot = packageRoot.parent.parent;
  String repositoryText(String path) =>
      File('${repositoryRoot.path}/$path').readAsStringSync();
  File packageFile(String path) => File('${packageRoot.path}/$path');

  final C0ConfigProvenance pin = c0ConfigContract.provenance;
  final String manifestText = repositoryText(c0ReleaseManifestPath);
  final String ledgerText = repositoryText(c0ReleaseLedgerPath);
  final String caseText = repositoryText(pin.sourceCase);

  final C0AuthenticatedRelease release;
  final String witness;
  try {
    // The committed manifest must itself be the canonical bytes the recipe
    // assumes, and must record the digest its own contents produce. Only then
    // is the witness handed to the shared authentication.
    final Map<String, Object?> manifest = _decodeObject(
      manifestText,
      'release manifest',
    );
    if ('${canonicalCompactJson(manifest)}\n' != manifestText) {
      throw const C0ReleaseAuthenticationFailure(
        '$c0ReleaseManifestPath is not compact-canonical',
      );
    }
    final Object? recordedDigest = manifest.remove('releaseDigest');
    witness = canonicalCompactJson(manifest);
    release = authenticateC0Release(
      manifestWithoutDigest: witness,
      ledgerText: ledgerText,
      caseText: caseText,
      pin: pin,
      projectedCases: c0ConfigContract.projectedCases,
    );
    if (recordedDigest != release.releaseDigest) {
      throw C0ReleaseAuthenticationFailure(
        '$c0ReleaseManifestPath records releaseDigest $recordedDigest, but its '
        'own bytes and ledger hash to ${release.releaseDigest}',
      );
    }
  } on C0ReleaseAuthenticationFailure catch (failure) {
    stderr.writeln(
      '$failure\n'
      'Refusing to project unauthenticated C0 bytes. A normative change '
      'requires a new c0-fixtures-rN release, a new accepted digest in '
      'lib/src/c0_config_contract.dart, and a release review.',
    );
    exit(1);
  }

  // The projection carries the vectors AND the two witnesses that authenticate
  // them, so the conformance gate needs no repository file to re-derive the
  // chain — and cannot be satisfied by a locally consistent forgery.
  final Map<String, Object?> projection = <String, Object?>{
    r'$generated': <String, Object?>{
      'tool': 'tool/gen_c0_projection.dart',
      'sourceCase': pin.sourceCase,
      'sourceCaseSha256': release.caseSha256,
      'domain': release.domain,
      'releaseId': pin.releaseId,
      'releaseDigest': release.releaseDigest,
      'releaseDigestDomain': c0ReleaseDigestDomain,
      'releaseManifestPath': c0ReleaseManifestPath,
      'releaseManifestWithoutDigest': witness,
      'releaseLedgerPath': c0ReleaseLedgerPath,
      'releaseLedgerEntry': release.ledgerEntry,
      'releaseLedger': ledgerText,
      'projectedCases': c0ConfigContract.projectedCases,
    },
    'c0Sections': release.c0Sections,
    for (final String name in c0ConfigContract.projectedCases)
      name: release.cases[name],
  };

  final String rendered =
      '${const JsonEncoder.withIndent('  ').convert(projection)}\n';
  final String checksum =
      '${sha256.convert(utf8.encode(rendered))}  config.json\n';
  final File fixture = packageFile(_fixturePath);
  final File checksumFile = packageFile(_checksumPath);

  if (check) {
    final bool fixtureMatches =
        fixture.existsSync() && fixture.readAsStringSync() == rendered;
    final bool checksumMatches =
        checksumFile.existsSync() &&
        checksumFile.readAsStringSync() == checksum;
    if (!fixtureMatches || !checksumMatches) {
      stderr.writeln(
        'C0 projection is stale: $_fixturePath or $_checksumPath does not '
        'match ${pin.sourceCase}. Run: dart run tool/gen_c0_projection.dart',
      );
      exit(1);
    }
    stdout.writeln(
      'C0 projection and checksum are up to date '
      '(${c0ConfigContract.projectedCases.length} vectors from '
      '${release.domain}, release ${pin.releaseId} '
      'authenticated as ${release.releaseDigest}).',
    );
    return;
  }

  fixture.parent.createSync(recursive: true);
  fixture.writeAsStringSync(rendered);
  checksumFile.writeAsStringSync(checksum);
  stdout.writeln(
    'Wrote $_fixturePath and $_checksumPath from ${pin.sourceCase} '
    '(release ${pin.releaseId} authenticated as ${release.releaseDigest}).',
  );
}

/// Recursively sorts object keys so a rendering is canonical.
Object? _sorted(Object? value) {
  if (value is Map<Object?, Object?>) {
    final List<String> keys =
        value.keys.map((Object? key) => key! as String).toList()..sort();
    return <String, Object?>{
      for (final String key in keys) key: _sorted(value[key]),
    };
  }
  if (value is List<Object?>) {
    return value.map(_sorted).toList();
  }
  return value;
}

/// Ledger path of [sourceCase], which is recorded relative to the C0 root.
String _ledgerEntryFor(String sourceCase) {
  const String prefix = '$c0ContractsRoot/';
  if (!sourceCase.startsWith(prefix) || sourceCase.length == prefix.length) {
    throw C0ReleaseAuthenticationFailure(
      'the accepted source case $sourceCase does not live under $prefix',
    );
  }
  return sourceCase.substring(prefix.length);
}

/// Domain implied by the normative case file name, e.g. `config`.
String _domainOf(String sourceCase) {
  final String name = sourceCase.split('/').last;
  if (!name.endsWith('.json') || name.length == '.json'.length) {
    throw C0ReleaseAuthenticationFailure(
      'the accepted source case $sourceCase is not a named .json case file',
    );
  }
  return name.substring(0, name.length - '.json'.length);
}

Map<String, Object?> _decodeObject(String text, String what) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (error) {
    throw C0ReleaseAuthenticationFailure('$what is not JSON: ${error.message}');
  }
  return _expectObject(decoded, what);
}

Map<String, Object?> _expectObject(Object? value, String what) {
  if (value is! Map<Object?, Object?>) {
    throw C0ReleaseAuthenticationFailure('$what is not a JSON object');
  }
  return value.cast<String, Object?>();
}

List<Object?> _expectList(Object? value, String what) {
  if (value is! List<Object?>) {
    throw C0ReleaseAuthenticationFailure('$what is not a JSON array');
  }
  return value;
}

void _expectKeys(
  Map<String, Object?> object,
  List<String> expected,
  String what,
) {
  final List<String> actual = object.keys.toList()..sort();
  final List<String> wanted = <String>[...expected]..sort();
  if (canonicalCompactJson(actual) != canonicalCompactJson(wanted)) {
    throw C0ReleaseAuthenticationFailure(
      '$what holds $actual, but the projection requires exactly $wanted',
    );
  }
}
