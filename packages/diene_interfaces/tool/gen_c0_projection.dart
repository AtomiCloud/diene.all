// Generates the C0 problem-envelope test projection for `diene_interfaces`.
//
// Every failure that crosses a `diene_interfaces` seam is an RFC 9457 `Problem`
// whose `type` URI is minted by the single C0 §2 builder. The authoritative
// §2 vectors live in the frozen C0 release `contracts/c0/cases/problem.json`
// (releaseId `c0-fixtures-r2`). This tool projects the subset this package's
// contract actually binds — the envelope member vocabulary and the type-URI
// template plus its worked example — into
// `test/fixtures/c0/problem-envelope.json`, and writes its matching SHA256SUMS
// entry.
//
// The `envelopes` and `catalogEntry` vectors are deliberately NOT projected:
// they bind `diene_problems`' own envelope codec and catalog EXPORT surface,
// which this package consumes rather than implements.
//
// Usage from the member directory:
//   dart run tool/gen_c0_projection.dart
//   dart run tool/gen_c0_projection.dart --check

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const String _releasePath = 'contracts/c0/RELEASE.json';
const String _casePath = 'contracts/c0/cases/problem.json';
const String _fixturePath = 'test/fixtures/c0/problem-envelope.json';
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
    'rfc9457Members': cases['rfc9457Members'],
    'extensions': cases['extensions'],
    'typeUriTemplate': cases['typeUriTemplate'],
    'typeUri': cases['typeUri'],
  };

  final String rendered =
      '${const JsonEncoder.withIndent('  ').convert(projection)}\n';
  final String checksum =
      '${sha256.convert(utf8.encode(rendered))}  problem-envelope.json\n';
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
