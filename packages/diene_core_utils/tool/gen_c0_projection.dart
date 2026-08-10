// Generates the C0 config-precedence test projection for `diene_core_utils`.
//
// This package implements the C0 §3 mechanics — layered deep-merge,
// case-insensitive key matching, `__`-indexed lists, blank-is-unset, and the
// no-JSON/no-comma rule — so the authoritative §3 vectors in the frozen C0
// release `contracts/c0/cases/config.json` (releaseId `c0-fixtures-r2`) are its
// conformance source. This tool projects the subset this package's contract
// actually binds into `test/fixtures/c0/config.json` and writes its matching
// SHA256SUMS entry.
//
// The `finalLayerValidation` vector is deliberately NOT projected: schema
// validation of the merged layer belongs to `diene_config`, which this package
// is consumed BY rather than implements. The projected vectors are exactly the
// four whose behaviour lives here.
//
// The C0 temporal (§1) half of this package's conformance is driven from
// `lib/src/c0_temporal_contract.dart` instead, because release r2 declares only
// the config, identity, problem, and result-wire domains — there is no temporal
// case file to project. That contract is digest-pinned in its own provenance and
// verified by `test/conformance/c0_temporal_test.dart`.
//
// Usage from the member directory:
//   dart run tool/gen_c0_projection.dart
//   dart run tool/gen_c0_projection.dart --check

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const String _releasePath = 'contracts/c0/RELEASE.json';
const String _casePath = 'contracts/c0/cases/config.json';
const String _fixturePath = 'test/fixtures/c0/config.json';
const String _checksumPath = 'test/fixtures/c0/SHA256SUMS';

/// The §3 vectors whose mechanics `diene_core_utils` implements.
const List<String> _projectedCases = <String>[
  'blankIsUnset',
  'caseInsensitiveKeyMatching',
  'layeringAndIndexedList',
  'noJsonNoComma',
];

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
  final Map<String, Object?> cases =
      (caseFile['cases']! as Map<Object?, Object?>).cast<String, Object?>();

  // Refuse to project on missing data rather than emitting a thin fixture that
  // would read as "these vectors passed" while binding nothing.
  final List<String> missing = <String>[
    for (final String name in _projectedCases)
      if (!cases.containsKey(name)) name,
  ];
  if (missing.isNotEmpty) {
    stderr.writeln(
      'C0 case $_casePath is missing required vectors: ${missing.join(', ')}. '
      'Refusing to write a partial projection.',
    );
    exit(1);
  }

  final Map<String, Object?> projection = <String, Object?>{
    r'$generated': <String, Object?>{
      'tool': 'tool/gen_c0_projection.dart',
      'sourceCase': _casePath,
      'domain': caseFile['domain'],
      'releaseId': release['releaseId'],
      'releaseDigest': release['releaseDigest'],
      'projectedCases': _projectedCases,
    },
    'c0Sections': caseFile['c0Sections'],
    for (final String name in _projectedCases) name: cases[name],
  };

  final String rendered =
      '${const JsonEncoder.withIndent('  ').convert(projection)}\n';
  final String checksum =
      '${sha256.convert(utf8.encode(rendered))}  config.json\n';
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
    stdout.writeln(
      'C0 projection and checksum are up to date '
      '(${_projectedCases.length} vectors from ${caseFile['domain']}).',
    );
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
