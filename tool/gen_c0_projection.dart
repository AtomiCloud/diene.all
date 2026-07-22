import 'dart:convert';
import 'dart:io';

const String _c0Root = 'contracts/c0';
const String _manifestPath = '$_c0Root/RELEASE.json';
const String _sumsPath = '$_c0Root/SHA256SUMS';
const String _casePath = '$_c0Root/cases/problem.json';
const String _domainSeparator = 'atomicloud.diene.c0-fixtures.release.v1';
const String _generatorPath = 'tool/gen_c0_projection.dart';
const String _fixturePath = 'test/fixtures/c0/problem-envelope.json';
const String _legacyFixturePath = 'test/fixtures/c0/problem_envelope.json';
const String _pinnedReleaseId = 'c0-fixtures-r2';
const String _pinnedReleaseDigest =
    '0e64439c681a22fb4f02285c082ed8ffb7b465e732fde4e49757e9e3c9a5783e';
const String _pinnedC0ProseDigest =
    '7dd7a06279f3078a5e195d4103d01ce9fd1b30a7d88178ec37c3e6f0465c7101';
const String _pinnedDartFamilyDigest =
    'ece72edbb18e2c45f6f16e3a4da2172862f7b044d4218292f90e5219da0b5bd6';
const String _pinnedResultDeepDiveDigest =
    '68e9ec021b3c286fa377bfb8ee02373cfab3146d5c6f43ce9d0085c27fefb164';
const String _pinnedFormatterDigest =
    'a5163b3ccf4e9da2956f3ed0f6866569fc34164050ca55e3e805ee1cc9a5bb02';
const List<String> _formatterExcludedPaths = <String>[
  '/contracts/c0/RELEASE.json',
  '/contracts/c0/cases/config.json',
  '/contracts/c0/cases/identity.json',
  '/contracts/c0/cases/problem.json',
  '/contracts/c0/cases/result-wire.json',
  '/contracts/c0/provenance/app-handoff.md',
  '/contracts/c0/provenance/config-precedence.md',
  '/contracts/c0/provenance/edge-docs.md',
  '/contracts/c0/provenance/home-claim.md',
  '/contracts/c0/provenance/onboarding-claim.md',
  '/contracts/c0/provenance/problem-catalog.md',
  '/contracts/c0/provenance/problem-schema.md',
  '/contracts/c0/provenance/result-semantics.md',
  '/contracts/c0/provenance/token-lifetimes.md',
  '/test/fixtures/c0/catalog-entry.json',
  '/test/fixtures/c0/config.json',
  '/test/fixtures/c0/envelope.json',
  '/test/fixtures/c0/identity.json',
  '/test/fixtures/c0/problem-envelope.json',
  '/test/fixtures/c0/result-wire.json',
  '/test/fixtures/c0/type-uri.json',
];
const List<String> _summedPaths = <String>[
  'README.md',
  'cases/config.json',
  'cases/identity.json',
  'cases/problem.json',
  'cases/result-wire.json',
  'provenance/PROVENANCE.md',
  'provenance/app-handoff.md',
  'provenance/config-precedence.md',
  'provenance/edge-docs.md',
  'provenance/home-claim.md',
  'provenance/onboarding-claim.md',
  'provenance/problem-catalog.md',
  'provenance/problem-schema.md',
  'provenance/result-semantics.md',
  'provenance/token-lifetimes.md',
];

void main(List<String> arguments) {
  if (arguments.length > 1 ||
      (arguments.isNotEmpty && arguments.single != '--check')) {
    stderr.writeln('usage: dart run $_generatorPath [--check]');
    exitCode = 64;
    return;
  }

  try {
    final _Release release = _loadRelease();
    final Map<String, Object?> caseFile = _loadCaseFile(release);
    final Map<String, List<int>> outputs = _renderOutputs(release, caseFile);
    _materialize(outputs, check: arguments.contains('--check'));
  } on Object catch (error) {
    stderr.writeln('C0 projection failed: $error');
    exitCode = 1;
  }
}

_Release _loadRelease() {
  final File manifestFile = File(_manifestPath);
  final List<int> manifestBytes = manifestFile.readAsBytesSync();
  final Map<String, Object?> manifest = _map(
    jsonDecode(utf8.decode(manifestBytes, allowMalformed: false)),
    _manifestPath,
  );

  _validateManifest(manifest);

  final List<int> canonicalManifest = utf8.encode(_compactCanonical(manifest));
  _expect(
    _bytesEqual(manifestBytes, canonicalManifest),
    '$_manifestPath is not compact-canonical',
  );

  final List<int> sumsBytes = File(_sumsPath).readAsBytesSync();
  final Map<String, String> sums = _validateSums(sumsBytes);

  final Map<String, Object?> payloadManifest = Map<String, Object?>.of(manifest)
    ..remove('releaseDigest');
  final List<int> payload = <int>[
    ...utf8.encode('$_domainSeparator\n'),
    ...utf8.encode(_compactCanonical(payloadManifest)),
    ...sumsBytes,
  ];
  final String digest = _sha256Hex(payload);
  _expect(
    digest == manifest['releaseDigest'],
    'complete-release digest mismatch: $digest != '
    '${manifest['releaseDigest']}',
  );
  _expect(digest == _pinnedReleaseDigest, 'release digest is not pinned R2');

  return _Release(manifest: manifest, digest: digest, sums: sums);
}

Map<String, Object?> _loadCaseFile(_Release release) {
  final File file = File(_casePath);
  final List<int> bytes = file.readAsBytesSync();
  _expect(
    _sha256Hex(bytes) == release.sums['cases/problem.json'],
    '$_casePath does not match authenticated SHA256SUMS',
  );
  final Map<String, Object?> value = _map(
    jsonDecode(utf8.decode(bytes, allowMalformed: false)),
    _casePath,
  );
  _validateCaseFile(value);
  _expect(
    _bytesEqual(bytes, utf8.encode(_prettyCanonical(value))),
    '$_casePath is not pretty-canonical',
  );
  return value;
}

void _validateManifest(Map<String, Object?> value) {
  _expectKeys(value, <String>{
    'releaseId',
    'contractVersion',
    'releaseDigest',
    'domains',
    'c0ProseSource',
    'secondarySources',
    'formatterPolicy',
  }, 'manifest');
  _validateManifestValues(value, 'manifest');

  final String releaseId = _string(value['releaseId'], 'releaseId');
  final RegExpMatch? match = RegExp(
    r'^c0-fixtures-r([1-9][0-9]*)$',
  ).firstMatch(releaseId);
  _expect(match != null, 'invalid releaseId');
  final int version = _integer(value['contractVersion'], 'contractVersion');
  _expect(int.parse(match!.group(1)!) == version, 'releaseId/version mismatch');
  _expect(releaseId == _pinnedReleaseId, 'releaseId is not pinned R2');
  _expect(version == 2, 'contractVersion is not 2');
  _expect(
    _string(value['releaseDigest'], 'releaseDigest') == _pinnedReleaseDigest,
    'manifest releaseDigest is not pinned R2',
  );
  _expect(
    _deepEqual(value['domains'], <String>[
      'config',
      'identity',
      'problem',
      'result-wire',
    ]),
    'domains must be [config, identity, problem, result-wire]',
  );

  final Map<String, Object?> source = _map(
    value['c0ProseSource'],
    'c0ProseSource',
  );
  _expectKeys(source, <String>{'path', 'sha256', 'note'}, 'c0ProseSource');
  _expect(source['path'] == 'goals/c0-contracts.md', 'wrong C0 prose path');
  _expect(source['sha256'] == _pinnedC0ProseDigest, 'wrong C0 prose digest');
  _expect(
    _string(source['note'], 'c0ProseSource.note').isNotEmpty,
    'empty C0 prose note',
  );

  final List<Object?> secondary = _list(
    value['secondarySources'],
    'secondarySources',
  );
  _expect(secondary.length == 2, 'R2 must have two secondary sources');
  final Map<String, Object?> dartSource = _map(
    secondary[0],
    'secondarySources[0]',
  );
  _expectKeys(dartSource, <String>{'path', 'sha256'}, 'secondarySources[0]');
  _expect(
    dartSource['path'] == 'goals/lib/dart-family.md',
    'wrong Dart-family source path',
  );
  _expect(
    dartSource['sha256'] == _pinnedDartFamilyDigest,
    'wrong Dart-family source digest',
  );
  final Map<String, Object?> resultSource = _map(
    secondary[1],
    'secondarySources[1]',
  );
  _expectKeys(resultSource, <String>{'path', 'sha256'}, 'secondarySources[1]');
  _expect(
    resultSource['path'] == 'goals/lib/result-deep-dive.md',
    'wrong Result deep-dive source path',
  );
  _expect(
    resultSource['sha256'] == _pinnedResultDeepDiveDigest,
    'wrong Result deep-dive source digest',
  );

  final Map<String, Object?> formatter = _map(
    value['formatterPolicy'],
    'formatterPolicy',
  );
  _expectKeys(formatter, <String>{
    'path',
    'prettierExcludedPaths',
    'sha256',
  }, 'formatterPolicy');
  _expect(formatter['path'] == '.prettierignore', 'wrong formatter policy');
  _expect(
    _deepEqual(formatter['prettierExcludedPaths'], _formatterExcludedPaths),
    'formatter exclusions are not the exact R2 paths',
  );
  _expect(
    formatter['sha256'] == _pinnedFormatterDigest,
    'wrong formatter policy digest',
  );
}

void _validateManifestValues(Object? value, String path) {
  if (value is String) {
    _expect(_safeAscii(value), '$path contains a forbidden string');
    return;
  }
  if (value is int || value is bool || value == null) {
    return;
  }
  if (value is num) {
    throw FormatException('$path contains a non-integer number');
  }
  if (value is List<Object?>) {
    for (int index = 0; index < value.length; index += 1) {
      _validateManifestValues(value[index], '$path[$index]');
    }
    return;
  }
  if (value is Map<String, Object?>) {
    for (final MapEntry<String, Object?> entry in value.entries) {
      _validateManifestValues(entry.value, '$path.${entry.key}');
    }
    return;
  }
  throw FormatException('$path contains an unsupported JSON value');
}

Map<String, String> _validateSums(List<int> bytes) {
  _expect(bytes.isNotEmpty && bytes.last == 10, 'SHA256SUMS must end in LF');
  _expect(!bytes.contains(13), 'SHA256SUMS contains CR bytes');
  final String text = utf8.decode(bytes, allowMalformed: false);
  final List<String> lines = text.substring(0, text.length - 1).split('\n');
  _expect(
    lines.isNotEmpty && lines.every((String line) => line.isNotEmpty),
    'SHA256SUMS contains an empty line',
  );
  final RegExp grammar = RegExp(
    r'^([0-9a-f]{64})  (README[.]md|cases/[^/]+[.]json|provenance/[^/]+[.]md)$',
  );
  final List<String> paths = <String>[];
  final Map<String, String> sums = <String, String>{};
  for (final String line in lines) {
    final RegExpMatch? match = grammar.firstMatch(line);
    _expect(match != null, 'malformed SHA256SUMS line: $line');
    final String path = match!.group(2)!;
    _expect(!sums.containsKey(path), 'duplicate sum path: $path');
    paths.add(path);
    sums[path] = match.group(1)!;
  }
  final List<String> sortedPaths = List<String>.of(paths)..sort();
  _expect(_deepEqual(paths, sortedPaths), 'SHA256SUMS paths are not sorted');
  _expect(
    _deepEqual(paths, _summedPaths),
    'SHA256SUMS paths are not the exact R2 inventory',
  );
  return sums;
}

void _validateCaseFile(Map<String, Object?> value) {
  _expectKeys(value, <String>{'domain', 'c0Sections', 'cases'}, 'case file');
  _validateCaseValues(value, 'case file');
  _expect(value['domain'] == 'problem', 'wrong case-file domain');
  _expect(
    _deepEqual(value['c0Sections'], <String>[
      '§2 Problem schema',
      '§14 Problem catalog schema',
    ]),
    'wrong Problem C0 sections',
  );
  final Map<String, Object?> cases = _map(value['cases'], 'cases');
  _expectKeys(cases, <String>{
    'rfc9457Members',
    'extensions',
    'typeUriTemplate',
    'typeUri',
    'envelopes',
    'catalogEntry',
  }, 'cases');
  _expect(
    _deepEqual(cases['rfc9457Members'], <String>[
      'type',
      'title',
      'status',
      'detail',
      'instance',
    ]),
    'wrong RFC 9457 members',
  );
  _expect(
    _deepEqual(cases['extensions'], <String>['data', 'recoverable']),
    'wrong Problem extensions',
  );
  _expect(
    _string(cases['typeUriTemplate'], 'typeUriTemplate').isNotEmpty,
    'missing type URI template',
  );

  final Map<String, Object?> typeUri = _map(cases['typeUri'], 'typeUri');
  _expectKeys(typeUri, <String>{'valid', 'invalid'}, 'typeUri');
  final List<Object?> validTypeUris = _list(typeUri['valid'], 'typeUri.valid');
  _expect(validTypeUris.isNotEmpty, 'missing valid type URI vector');
  final Map<String, Object?> typeVector = _map(
    validTypeUris.first,
    'typeUri.valid[0]',
  );
  _expectKeys(typeVector, <String>{
    'expectedTypeUri',
    'segments',
  }, 'typeUri.valid[0]');
  final Map<String, Object?> segments = _map(
    typeVector['segments'],
    'typeUri.valid[0].segments',
  );
  _expect(
    _deepEqual(segments, <String, Object?>{
      'host': 'docs.raichu.cluster.atomi.cloud',
      'id': 'entity-not-found',
      'landscape': 'raichu',
      'module': 'api',
      'platform': 'dotnet',
      'scheme': 'https',
      'service': 'user',
      'version': 'v1',
    }),
    'wrong authoritative type URI segments',
  );

  final Map<String, Object?> envelopes = _map(cases['envelopes'], 'envelopes');
  _expectKeys(envelopes, <String>{'valid', 'invalid'}, 'envelopes');
  final List<Object?> validEnvelopes = _list(
    envelopes['valid'],
    'envelopes.valid',
  );
  _expect(validEnvelopes.isNotEmpty, 'missing valid Problem envelope');
  final Map<String, Object?> envelope = _map(
    validEnvelopes.first,
    'envelopes.valid[0]',
  );
  _expectKeys(envelope, <String>{
    'type',
    'title',
    'status',
    'detail',
    'instance',
    'recoverable',
    'data',
  }, 'envelopes.valid[0]');
  _expect(
    envelope['type'] == typeVector['expectedTypeUri'],
    'envelope/type URI vector mismatch',
  );
  _expect(_string(envelope['title'], 'envelope.title').isNotEmpty, 'bad title');
  _integer(envelope['status'], 'envelope.status');
  _string(envelope['detail'], 'envelope.detail');
  _string(envelope['instance'], 'envelope.instance');
  _expect(envelope['recoverable'] is bool, 'envelope.recoverable must be bool');
  final Map<String, Object?> data = _map(envelope['data'], 'envelope.data');
  _expectKeys(data, <String>{'id', 'resource'}, 'envelope.data');
  _expect(data['id'] == 42, 'wrong envelope data.id');
  _expect(data['resource'] == 'user', 'wrong envelope data.resource');

  final Map<String, Object?> catalog = _map(
    cases['catalogEntry'],
    'catalogEntry',
  );
  _expectKeys(catalog, <String>{'shape', 'samples'}, 'catalogEntry');
}

void _validateCaseValues(Object? value, String path) {
  if (value is num) {
    _expect(value is int, '$path contains a non-integer number');
    return;
  }
  if (value is String || value is bool || value == null) {
    return;
  }
  if (value is List<Object?>) {
    for (int index = 0; index < value.length; index += 1) {
      _validateCaseValues(value[index], '$path[$index]');
    }
    return;
  }
  if (value is Map<String, Object?>) {
    for (final MapEntry<String, Object?> entry in value.entries) {
      _expect(_safeAscii(entry.key), '$path has a forbidden object key');
      _validateCaseValues(entry.value, '$path.${entry.key}');
    }
    return;
  }
  throw FormatException('$path contains an unsupported JSON value');
}

Map<String, List<int>> _renderOutputs(
  _Release release,
  Map<String, Object?> caseFile,
) {
  final Map<String, Object?> cases = _map(caseFile['cases'], 'cases');
  final Map<String, Object?> envelopes = _map(cases['envelopes'], 'envelopes');
  final Map<String, Object?> envelope = _map(
    _list(envelopes['valid'], 'envelopes.valid').first,
    'envelopes.valid[0]',
  );
  final Map<String, Object?> generated = <String, Object?>{
    'generator': _generatorPath,
    'releaseDigest': release.digest,
    'releaseId': release.manifest['releaseId'],
  };
  final Map<String, List<int>> outputs = <String, List<int>>{
    _fixturePath: utf8.encode(
      _prettyCanonical(<String, Object?>{
        r'$generated': generated,
        ...envelope,
      }),
    ),
  };
  final StringBuffer sums = StringBuffer();
  sums.writeln('${_sha256Hex(outputs[_fixturePath]!)}  problem-envelope.json');
  outputs['test/fixtures/c0/SHA256SUMS'] = utf8.encode(sums.toString());
  return outputs;
}

void _materialize(Map<String, List<int>> outputs, {required bool check}) {
  final Directory temporary = Directory.systemTemp.createTempSync(
    'diene-c0-api-engine-',
  );
  try {
    for (final MapEntry<String, List<int>> output in outputs.entries) {
      final File file = File('${temporary.path}/${output.key}');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(output.value, flush: true);
    }

    final File legacy = File(_legacyFixturePath);
    if (check) {
      _expect(
        !legacy.existsSync(),
        'STALE: delete $_legacyFixturePath; generated names are kebab-case',
      );
    } else if (legacy.existsSync()) {
      legacy.deleteSync();
    }

    for (final String path in outputs.keys) {
      final File generated = File('${temporary.path}/$path');
      final File committed = File(path);
      if (check) {
        _expect(committed.existsSync(), 'STALE: missing $path');
        _expect(
          _bytesEqual(committed.readAsBytesSync(), generated.readAsBytesSync()),
          'STALE: $path differs from regeneration; run '
          'dart run $_generatorPath',
        );
      } else {
        committed.parent.createSync(recursive: true);
        committed.writeAsBytesSync(generated.readAsBytesSync(), flush: true);
      }
    }
  } finally {
    temporary.deleteSync(recursive: true);
  }
  stdout.writeln(
    check
        ? 'C0 API projection matches the authenticated R2 release'
        : 'generated C0 API projection from the authenticated R2 release',
  );
}

String _compactCanonical(Map<String, Object?> value) =>
    '${jsonEncode(_sortJson(value))}\n';

String _prettyCanonical(Map<String, Object?> value) =>
    '${const JsonEncoder.withIndent('  ').convert(_sortJson(value))}\n';

Object? _sortJson(Object? value) {
  if (value is Map<String, Object?>) {
    final List<String> keys = value.keys.toList()..sort();
    return <String, Object?>{
      for (final String key in keys) key: _sortJson(value[key]),
    };
  }
  if (value is List<Object?>) {
    return value.map<Object?>(_sortJson).toList(growable: false);
  }
  return value;
}

Map<String, Object?> _map(Object? value, String context) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$context must be an object');
  }
  return Map<String, Object?>.from(value);
}

List<Object?> _list(Object? value, String context) {
  if (value is! List<dynamic>) {
    throw FormatException('$context must be an array');
  }
  return List<Object?>.from(value);
}

String _string(Object? value, String context) {
  if (value is! String) {
    throw FormatException('$context must be a string');
  }
  return value;
}

int _integer(Object? value, String context) {
  if (value is! int) {
    throw FormatException('$context must be an integer');
  }
  return value;
}

void _expectKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String context,
) {
  final Set<String> actual = value.keys.toSet();
  _expect(
    actual.length == expected.length && actual.containsAll(expected),
    '$context keys differ: $actual != $expected',
  );
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw FormatException(message);
  }
}

bool _safeAscii(String value) => value.runes.every(
  (int rune) => rune >= 0x20 && rune <= 0x7e && rune != 0x22 && rune != 0x5c,
);

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (int index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

bool _deepEqual(Object? left, Object? right) =>
    jsonEncode(left) == jsonEncode(right);

String _sha256Hex(List<int> input) {
  const int mask32 = 0xffffffff;
  const List<int> roundConstants = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];
  final List<int> bytes = List<int>.of(input)..add(0x80);
  while (bytes.length % 64 != 56) {
    bytes.add(0);
  }
  final int bitLength = input.length * 8;
  for (int shift = 56; shift >= 0; shift -= 8) {
    bytes.add((bitLength >> shift) & 0xff);
  }

  final List<int> state = <int>[
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];
  final List<int> schedule = List<int>.filled(64, 0);
  for (int offset = 0; offset < bytes.length; offset += 64) {
    for (int index = 0; index < 16; index += 1) {
      final int byteOffset = offset + (index * 4);
      schedule[index] =
          (bytes[byteOffset] << 24) |
          (bytes[byteOffset + 1] << 16) |
          (bytes[byteOffset + 2] << 8) |
          bytes[byteOffset + 3];
    }
    for (int index = 16; index < 64; index += 1) {
      final int value15 = schedule[index - 15];
      final int sigma0 =
          _rotateRight32(value15, 7) ^
          _rotateRight32(value15, 18) ^
          (value15 >>> 3);
      final int value2 = schedule[index - 2];
      final int sigma1 =
          _rotateRight32(value2, 17) ^
          _rotateRight32(value2, 19) ^
          (value2 >>> 10);
      schedule[index] =
          (schedule[index - 16] + sigma0 + schedule[index - 7] + sigma1) &
          mask32;
    }

    int a = state[0];
    int b = state[1];
    int c = state[2];
    int d = state[3];
    int e = state[4];
    int f = state[5];
    int g = state[6];
    int h = state[7];
    for (int index = 0; index < 64; index += 1) {
      final int bigSigma1 =
          _rotateRight32(e, 6) ^ _rotateRight32(e, 11) ^ _rotateRight32(e, 25);
      final int choose = (e & f) ^ ((~e & mask32) & g);
      final int temporary1 =
          (h + bigSigma1 + choose + roundConstants[index] + schedule[index]) &
          mask32;
      final int bigSigma0 =
          _rotateRight32(a, 2) ^ _rotateRight32(a, 13) ^ _rotateRight32(a, 22);
      final int majority = (a & b) ^ (a & c) ^ (b & c);
      final int temporary2 = (bigSigma0 + majority) & mask32;

      h = g;
      g = f;
      f = e;
      e = (d + temporary1) & mask32;
      d = c;
      c = b;
      b = a;
      a = (temporary1 + temporary2) & mask32;
    }

    state[0] = (state[0] + a) & mask32;
    state[1] = (state[1] + b) & mask32;
    state[2] = (state[2] + c) & mask32;
    state[3] = (state[3] + d) & mask32;
    state[4] = (state[4] + e) & mask32;
    state[5] = (state[5] + f) & mask32;
    state[6] = (state[6] + g) & mask32;
    state[7] = (state[7] + h) & mask32;
  }

  return state
      .map((int value) => value.toRadixString(16).padLeft(8, '0'))
      .join();
}

int _rotateRight32(int value, int bits) =>
    ((value >>> bits) | ((value << (32 - bits)) & 0xffffffff)) & 0xffffffff;

final class _Release {
  const _Release({
    required this.manifest,
    required this.digest,
    required this.sums,
  });

  final Map<String, Object?> manifest;
  final String digest;
  final Map<String, String> sums;
}
