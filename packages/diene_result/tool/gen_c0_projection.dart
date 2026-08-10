// Generates the C0 Result-wire test projection for `diene_result`.
//
// The authoritative section-5 Result/Option wire vectors live in the frozen
// C0 release `contracts/c0/cases/result-wire.json` (releaseId
// `c0-fixtures-r2`). This tool projects those vectors 1:1 into
// `test/fixtures/c0/result-wire.json` and writes its matching SHA256SUMS entry.
//
// Usage from the member directory:
//   dart run tool/gen_c0_projection.dart
//   dart run tool/gen_c0_projection.dart --check

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const String _releasePath = 'contracts/c0/RELEASE.json';
const String _casePath = 'contracts/c0/cases/result-wire.json';
const String _fixturePath = 'test/fixtures/c0/result-wire.json';
const String _checksumPath = 'test/fixtures/c0/SHA256SUMS';

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
  final String checksum =
      '${sha256.convert(utf8.encode(rendered))}  result-wire.json\n';
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
