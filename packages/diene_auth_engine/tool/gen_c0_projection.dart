// Generates the C0 `identity` test projection for `diene_auth_engine`.
//
// The authoritative vectors live in the FROZEN C0 release
// `contracts/c0/cases/identity.json` (releaseId `c0-fixtures-r2`,
// contractVersion 2), whose prose provenance is
// `contracts/c0/provenance/{app-handoff,edge-docs,home-claim,onboarding-claim,
// token-lifetimes}.md`. This tool projects that case file into
// `test/fixtures/c0/identity.json` and writes its matching `SHA256SUMS`.
//
// UNLIKE the sibling `diene_interfaces` projection, which deliberately narrows
// to the subset it binds, this one projects the WHOLE identity domain: every
// case in it — appHandoff (§7), onboardingClaim (§8), docB (§10),
// tokenLifetimes (§12), homeClaim (§13) and resourceAudience (§8/S7) — is
// implemented HERE rather than consumed from elsewhere. `_expectedCases`
// asserts that, so a case ADDED to the frozen release cannot slip past this
// package silently unbound; the tool fails instead.
//
// The rendering is `JsonEncoder.withIndent('  ')` plus a trailing newline,
// which is byte-identical to prettier's canonical JSON output. That is what
// keeps the fixture stable under `treefmt`, and it is the reason no
// `.prettierignore` entry is needed — `.prettierignore` is digest-locked by
// `contracts/c0/RELEASE.json` `formatterPolicy.sha256` and its paths are
// anchored at the repository root, so it could not cover a member-package
// fixture anyway.
//
// Usage from the member directory:
//   dart run tool/gen_c0_projection.dart
//   dart run tool/gen_c0_projection.dart --check

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const String _releasePath = 'contracts/c0/RELEASE.json';
const String _casePath = 'contracts/c0/cases/identity.json';
const String _fixturePath = 'test/fixtures/c0/identity.json';
const String _checksumPath = 'test/fixtures/c0/SHA256SUMS';

/// Every case this package binds. The projection REFUSES to run if the frozen
/// release and this list disagree in either direction — a missing case means a
/// broken release, an unexpected one means new contract surface nobody has
/// bound yet. Refusing to judge beats emitting a fixture that silently drops a
/// vector.
const Set<String> _expectedCases = <String>{
  'appHandoff',
  'docB',
  'homeClaim',
  'onboardingClaim',
  'resourceAudience',
  'tokenLifetimes',
};

final Directory _packageRoot = File.fromUri(Platform.script).parent.parent;
final Directory _repositoryRoot = _packageRoot.parent.parent;

void main(List<String> args) {
  final bool check = args.contains('--check');

  final Map<String, Object?> release = _readJsonObject(
    _repositoryFile(_releasePath),
  );
  final Map<String, Object?> caseFile = _readJsonObject(
    _repositoryFile(_casePath),
  );

  if (caseFile['domain'] != 'identity') {
    stderr.writeln(
      'C0 projection: expected domain "identity", got "${caseFile['domain']}" '
      'in $_casePath',
    );
    exit(1);
  }

  final Map<String, Object?> cases =
      (caseFile['cases']! as Map<Object?, Object?>).cast<String, Object?>();

  // Assert the partition is TOTAL in both directions before projecting.
  final Set<String> actual = cases.keys.toSet();
  final Set<String> missing = _expectedCases.difference(actual);
  final Set<String> unexpected = actual.difference(_expectedCases);
  if (missing.isNotEmpty || unexpected.isNotEmpty) {
    stderr.writeln(
      'C0 projection: identity case set does not match what this package '
      'binds.\n'
      '  missing:    ${missing.isEmpty ? '(none)' : missing.join(', ')}\n'
      '  unexpected: ${unexpected.isEmpty ? '(none)' : unexpected.join(', ')}\n'
      'Bind the new surface (or correct _expectedCases) rather than widening '
      'this tool.',
    );
    exit(1);
  }

  final Map<String, Object?> projection = <String, Object?>{
    r'$generated': <String, Object?>{
      'tool': 'tool/gen_c0_projection.dart',
      'sourceCase': _casePath,
      'domain': caseFile['domain'],
      'c0Sections': caseFile['c0Sections'],
      'releaseId': release['releaseId'],
      'releaseDigest': release['releaseDigest'],
    },
    for (final String name in _expectedCases.toList()..sort())
      name: cases[name],
  };

  final String rendered =
      '${const JsonEncoder.withIndent('  ').convert(projection)}\n';
  final String checksum =
      '${sha256.convert(utf8.encode(rendered))}  identity.json\n';
  final File fixture = _packageFile(_fixturePath);
  final File checksumFile = _packageFile(_checksumPath);

  if (check) {
    final bool fixtureMatches =
        fixture.existsSync() && fixture.readAsStringSync() == rendered;
    final bool checksumMatches =
        checksumFile.existsSync() &&
        checksumFile.readAsStringSync() == checksum;
    if (!fixtureMatches || !checksumMatches) {
      stderr.writeln(
        'C0 projection is stale: $_fixturePath or $_checksumPath does not '
        'match $_casePath. Run: dart run tool/gen_c0_projection.dart',
      );
      exit(1);
    }
    stdout.writeln('C0 projection and checksum are up to date.');
    return;
  }

  fixture.parent.createSync(recursive: true);
  fixture.writeAsStringSync(rendered);
  checksumFile.writeAsStringSync(checksum);
  stdout.writeln('Wrote $_fixturePath and $_checksumPath from $_casePath.');
}

File _repositoryFile(String path) => File('${_repositoryRoot.path}/$path');

File _packageFile(String path) => File('${_packageRoot.path}/$path');

Map<String, Object?> _readJsonObject(File file) =>
    (jsonDecode(file.readAsStringSync()) as Map<Object?, Object?>)
        .cast<String, Object?>();
