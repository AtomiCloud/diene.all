// Generates the C0 Result-wire test projection for `diene_result`.
//
// The authoritative section-5 Result/Option wire vectors live in the frozen
// C0 release `contracts/c0/cases/result-wire.json` (releaseId `c0-fixtures-r2`).
// This tool projects those vectors 1:1 into `test/fixtures/c0/result-wire.json`
// and writes the matching `test/fixtures/c0/SHA256SUMS`, so the conformance
// suite reads only the neutral, source-owned contract — never a hand-authored
// fixture.
//
// Usage:
//   dart tool/gen_c0_projection.dart          # (re)write the projection
//   dart tool/gen_c0_projection.dart --check  # fail if the projection drifted
//
// It depends only on `dart:convert`/`dart:io`; the byte-for-byte SHA256SUMS
// file is produced by `sha256sum` in the release gate, and `--check` compares
// the generated JSON against the committed bytes.

import 'dart:convert';
import 'dart:io';

const String _releasePath = 'contracts/c0/RELEASE.json';
const String _casePath = 'contracts/c0/cases/result-wire.json';
const String _fixtureDir = 'test/fixtures/c0';
const String _fixturePath = '$_fixtureDir/result-wire.json';

void main(List<String> args) {
  final bool check = args.contains('--check');

  final Map<String, Object?> release = _readJsonObject(_releasePath);
  final Map<String, Object?> caseFile = _readJsonObject(_casePath);
  final Map<String, Object?> cases =
      (caseFile['cases']! as Map<Object?, Object?>).cast<String, Object?>();

  final Map<String, Object?> projection = <String, Object?>{
    r'$generated': <String, Object?>{
      'tool': 'tool/gen_c0_projection.dart',
      'sourceCase': _casePath,
      'domain': caseFile['domain'],
      'releaseId': release['releaseId'],
      'releaseDigest': release['releaseDigest'],
    },
    'combinators': cases['combinators'],
    'optionTags': cases['optionTags'],
    'options': cases['options'],
    'resultTags': cases['resultTags'],
    'results': cases['results'],
  };

  final String rendered =
      '${const JsonEncoder.withIndent('  ').convert(projection)}\n';

  if (check) {
    final File fixture = File(_fixturePath);
    if (!fixture.existsSync() || fixture.readAsStringSync() != rendered) {
      stderr.writeln(
        'C0 projection is stale: $_fixturePath does not match '
        '$_casePath. Run: dart tool/gen_c0_projection.dart',
      );
      exit(1);
    }
    stdout.writeln('C0 projection is up to date.');
    return;
  }

  Directory(_fixtureDir).createSync(recursive: true);
  File(_fixturePath).writeAsStringSync(rendered);
  stdout.writeln('Wrote $_fixturePath from $_casePath.');
}

Map<String, Object?> _readJsonObject(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as Map<Object?, Object?>)
        .cast<String, Object?>();
