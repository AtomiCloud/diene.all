import 'dart:convert';
import 'dart:io';

const String _c0Root = 'contracts/c0';
const String _manifestPath = '$_c0Root/RELEASE.json';
const String _sumsPath = '$_c0Root/SHA256SUMS';
const String _casePath = '$_c0Root/cases/config.json';
const String _domainSeparator = 'atomicloud.diene.c0-fixtures.release.v1';
const String _generatorPath = 'tool/gen_c0_projection.dart';
const List<String> _formatterExcludedPaths = <String>[
  '/contracts/c0/RELEASE.json',
  '/contracts/c0/cases/config.json',
  '/contracts/c0/cases/problem.json',
  '/contracts/c0/provenance/config-precedence.md',
  '/contracts/c0/provenance/problem-catalog.md',
  '/contracts/c0/provenance/problem-schema.md',
  '/test/fixtures/c0/catalog-entry.json',
  '/test/fixtures/c0/config.json',
  '/test/fixtures/c0/envelope.json',
  '/test/fixtures/c0/type-uri.json',
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
    final Map<String, Object?> caseFile = _loadCaseFile();
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

  // The strict schema is intentionally the first validation step.
  _validateManifest(manifest);

  final List<int> canonicalManifest = utf8.encode(_compactCanonical(manifest));
  _expect(
    _bytesEqual(manifestBytes, canonicalManifest),
    '$_manifestPath is not compact-canonical',
  );

  final Map<String, Object?> formatterPolicy = _map(
    manifest['formatterPolicy'],
    'formatterPolicy',
  );
  final File policyFile = File(formatterPolicy['path']! as String);
  final List<int> policyBytes = policyFile.readAsBytesSync();
  _expect(
    _sha256Hex(policyBytes) == formatterPolicy['sha256'],
    'formatter policy digest mismatch',
  );
  final String expectedPolicy = '${_formatterExcludedPaths.join('\n')}\n';
  _expect(
    _bytesEqual(policyBytes, utf8.encode(expectedPolicy)),
    'formatter policy does not contain the exact manifest exclusions',
  );

  final List<int> sumsBytes = File(_sumsPath).readAsBytesSync();
  _validateSums(sumsBytes);

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

  return _Release(manifest: manifest, digest: digest);
}

Map<String, Object?> _loadCaseFile() {
  final File file = File(_casePath);
  final List<int> bytes = file.readAsBytesSync();
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
  _expect(
    RegExp(
      r'^[0-9a-f]{64}$',
    ).hasMatch(_string(value['releaseDigest'], 'releaseDigest')),
    'invalid releaseDigest',
  );
  _expect(
    _deepEqual(value['domains'], <String>['config', 'problem']),
    'domains must be [config, problem]',
  );

  final Map<String, Object?> source = _map(
    value['c0ProseSource'],
    'c0ProseSource',
  );
  _expectKeys(source, <String>{'path', 'sha256', 'note'}, 'c0ProseSource');
  _expect(source['path'] == 'goals/c0-contracts.md', 'wrong C0 prose path');
  _expect(
    RegExp(
      r'^[0-9a-f]{64}$',
    ).hasMatch(_string(source['sha256'], 'c0ProseSource.sha256')),
    'invalid C0 prose digest',
  );
  _expect(
    _string(source['note'], 'c0ProseSource.note').isNotEmpty,
    'empty C0 prose note',
  );

  final List<Object?> secondary = _list(
    value['secondarySources'],
    'secondarySources',
  );
  _expect(secondary.length == 1, 'r1 must have one secondary source');
  final Map<String, Object?> dartSource = _map(
    secondary.single,
    'secondarySources[0]',
  );
  _expectKeys(dartSource, <String>{'path', 'sha256'}, 'secondarySources[0]');
  _expect(
    dartSource['path'] == 'goals/lib/dart-family.md',
    'wrong Dart-family source path',
  );
  _expect(
    RegExp(
      r'^[0-9a-f]{64}$',
    ).hasMatch(_string(dartSource['sha256'], 'secondarySources[0].sha256')),
    'invalid Dart-family source digest',
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
    'formatter exclusions are not the exact RB-337 paths',
  );
  _expect(
    RegExp(
      r'^[0-9a-f]{64}$',
    ).hasMatch(_string(formatter['sha256'], 'formatterPolicy.sha256')),
    'invalid formatter policy digest',
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

void _validateSums(List<int> bytes) {
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
  final Map<String, String> expectedDigests = <String, String>{};
  for (final String line in lines) {
    final RegExpMatch? match = grammar.firstMatch(line);
    _expect(match != null, 'malformed SHA256SUMS line: $line');
    final String path = match!.group(2)!;
    _expect(!expectedDigests.containsKey(path), 'duplicate sum path: $path');
    paths.add(path);
    expectedDigests[path] = match.group(1)!;
  }
  final List<String> sortedPaths = List<String>.of(paths)..sort();
  _expect(_deepEqual(paths, sortedPaths), 'SHA256SUMS paths are not sorted');

  final List<String> covered = <String>['README.md'];
  covered.addAll(_eligibleFiles('cases', '.json'));
  covered.addAll(_eligibleFiles('provenance', '.md'));
  covered.sort();
  _expect(_deepEqual(paths, covered), 'SHA256SUMS coverage is not exhaustive');

  for (final MapEntry<String, String> entry in expectedDigests.entries) {
    final File file = File('$_c0Root/${entry.key}');
    _expect(file.existsSync(), 'summed file is missing: ${entry.key}');
    final String actual = _sha256Hex(file.readAsBytesSync());
    _expect(actual == entry.value, 'digest mismatch for ${entry.key}');
  }
}

List<String> _eligibleFiles(String directory, String extension) {
  final String prefix = '$_c0Root/';
  return Directory('$_c0Root/$directory')
      .listSync(followLinks: false)
      .whereType<File>()
      .map((File file) => file.path.substring(prefix.length))
      .where((String path) => path.endsWith(extension))
      .toList(growable: false);
}

void _validateCaseFile(Map<String, Object?> value) {
  _expectKeys(value, <String>{'domain', 'c0Sections', 'cases'}, 'case file');
  _validateCaseValues(value, 'case file');
  _expect(value['domain'] == 'config', 'wrong case-file domain');
  _expect(
    _deepEqual(value['c0Sections'], <String>['§3 Config precedence']),
    'wrong Config C0 sections',
  );
  final Map<String, Object?> cases = _map(value['cases'], 'cases');
  _expectKeys(cases, <String>{
    'layeringAndIndexedList',
    'blankIsUnset',
    'noJsonNoComma',
    'caseInsensitiveKeyMatching',
    'finalLayerValidation',
  }, 'cases');
  _expectKeys(
    _map(cases['layeringAndIndexedList'], 'layeringAndIndexedList'),
    <String>{
      'baseYaml',
      'defines',
      'developmentYaml',
      'expected',
      'landscapeYaml',
      'prefix',
    },
    'layeringAndIndexedList',
  );
  _expectKeys(_map(cases['blankIsUnset'], 'blankIsUnset'), <String>{
    'baseYaml',
    'defines',
    'expected',
    'prefix',
  }, 'blankIsUnset');
  final Map<String, Object?> rejected = _map(
    cases['noJsonNoComma'],
    'noJsonNoComma',
  );
  _expectKeys(rejected, <String>{'rejected'}, 'noJsonNoComma');
  _expect(
    _list(rejected['rejected'], 'noJsonNoComma.rejected').isNotEmpty,
    'noJsonNoComma.rejected must not be empty',
  );
  final Map<String, Object?> matching = _map(
    cases['caseInsensitiveKeyMatching'],
    'caseInsensitiveKeyMatching',
  );
  _expectKeys(matching, <String>{
    'baseYaml',
    'prefix',
    'variants',
  }, 'caseInsensitiveKeyMatching');
  _expect(
    _list(
      matching['variants'],
      'caseInsensitiveKeyMatching.variants',
    ).isNotEmpty,
    'caseInsensitiveKeyMatching.variants must not be empty',
  );
  final Map<String, Object?> validation = _map(
    cases['finalLayerValidation'],
    'finalLayerValidation',
  );
  _expectKeys(validation, <String>{'invalid'}, 'finalLayerValidation');
  _expectKeys(
    _map(validation['invalid'], 'finalLayerValidation.invalid'),
    <String>{'baseYaml', 'defines', 'prefix'},
    'finalLayerValidation.invalid',
  );
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
  final Map<String, Object?> generated = <String, Object?>{
    'generator': _generatorPath,
    'releaseDigest': release.digest,
    'releaseId': release.manifest['releaseId'],
  };
  final Map<String, List<int>> outputs = <String, List<int>>{
    'lib/src/c0_config_contract.g.dart': utf8.encode(
      _renderDart(release, caseFile),
    ),
    'test/fixtures/c0/config.json': utf8.encode(
      _prettyCanonical(<String, Object?>{
        r'$generated': generated,
        'c0Sections': caseFile['c0Sections'],
        'cases': cases,
        'domain': caseFile['domain'],
      }),
    ),
  };

  final List<String> projectedJson =
      outputs.keys
          .where(
            (String path) =>
                path.startsWith('test/fixtures/c0/') && path.endsWith('.json'),
          )
          .toList()
        ..sort();
  final StringBuffer sums = StringBuffer();
  for (final String path in projectedJson) {
    final String name = path.substring('test/fixtures/c0/'.length);
    sums.writeln('${_sha256Hex(outputs[path]!)}  $name');
  }
  outputs['test/fixtures/c0/SHA256SUMS'] = utf8.encode(sums.toString());
  return outputs;
}

String _renderDart(_Release release, Map<String, Object?> caseFile) {
  final Map<String, Object?> manifest = release.manifest;
  final Map<String, Object?> source = _map(
    manifest['c0ProseSource'],
    'c0ProseSource',
  );
  final Map<String, Object?> formatter = _map(
    manifest['formatterPolicy'],
    'formatterPolicy',
  );
  final List<Object?> secondary = _list(
    manifest['secondarySources'],
    'secondarySources',
  );
  final Map<String, Object?> cases = _map(caseFile['cases'], 'cases');
  final String secondaryPins = secondary
      .map((Object? value) {
        final Map<String, Object?> pin = _map(value, 'secondary source');
        return 'C0ConfigSourcePin(path: ${_dartString(pin['path']! as String)}, '
            'sha256: ${_dartString(pin['sha256']! as String)})';
      })
      .join(',');

  return '''// GENERATED by $_generatorPath from ${manifest['releaseId']} — DO NOT EDIT.
library;

/// One immutable prose-source pin carried by the generated C0 projection.
final class C0ConfigSourcePin {
  const C0ConfigSourcePin({required this.path, required this.sha256, this.note});
  final String path;
  final String sha256;
  final String? note;
}

/// Authenticated identity of the neutral C0 release used for this projection.
final class C0ConfigReleaseProvenance {
  const C0ConfigReleaseProvenance({
    required this.releaseId,
    required this.contractVersion,
    required this.releaseDigest,
    required this.c0ProseSource,
    required this.secondarySources,
    required this.formatterPolicyPath,
    required this.formatterPolicySha256,
    required this.prettierExcludedPaths,
  });
  final String releaseId;
  final int contractVersion;
  final String releaseDigest;
  final C0ConfigSourcePin c0ProseSource;
  final List<C0ConfigSourcePin> secondarySources;
  final String formatterPolicyPath;
  final String formatterPolicySha256;
  final List<String> prettierExcludedPaths;
}

/// Generated C0 §3 Config vectors from the neutral release.
final class C0ConfigContract {
  const C0ConfigContract({
    required this.provenance,
    required this.c0Sections,
    required this.layeringAndIndexedList,
    required this.blankIsUnset,
    required this.noJsonNoComma,
    required this.caseInsensitiveKeyMatching,
    required this.finalLayerValidation,
  });
  final C0ConfigReleaseProvenance provenance;
  final List<String> c0Sections;
  final Map<String, Object?> layeringAndIndexedList;
  final Map<String, Object?> blankIsUnset;
  final Map<String, Object?> noJsonNoComma;
  final Map<String, Object?> caseInsensitiveKeyMatching;
  final Map<String, Object?> finalLayerValidation;
}

/// The generated projection of ${manifest['releaseId']}.
const C0ConfigContract c0ConfigContract = C0ConfigContract(
  provenance: C0ConfigReleaseProvenance(
    releaseId: ${_dartString(manifest['releaseId']! as String)},
    contractVersion: ${manifest['contractVersion']},
    releaseDigest: ${_dartString(release.digest)},
    c0ProseSource: C0ConfigSourcePin(
      path: ${_dartString(source['path']! as String)},
      sha256: ${_dartString(source['sha256']! as String)},
      note: ${_dartString(source['note']! as String)},
    ),
    secondarySources: <C0ConfigSourcePin>[$secondaryPins],
    formatterPolicyPath: ${_dartString(formatter['path']! as String)},
    formatterPolicySha256: ${_dartString(formatter['sha256']! as String)},
    prettierExcludedPaths: ${_dartStringList(_formatterExcludedPaths)},
  ),
  c0Sections: ${_dartStringList(_list(caseFile['c0Sections'], 'c0Sections').cast<String>())},
  layeringAndIndexedList: ${_dartLiteral(cases['layeringAndIndexedList'])},
  blankIsUnset: ${_dartLiteral(cases['blankIsUnset'])},
  noJsonNoComma: ${_dartLiteral(cases['noJsonNoComma'])},
  caseInsensitiveKeyMatching: ${_dartLiteral(cases['caseInsensitiveKeyMatching'])},
  finalLayerValidation: ${_dartLiteral(cases['finalLayerValidation'])},
);
''';
}

void _materialize(Map<String, List<int>> outputs, {required bool check}) {
  final Directory temporary = Directory.systemTemp.createTempSync(
    'diene-c0-config-',
  );
  try {
    for (final MapEntry<String, List<int>> output in outputs.entries) {
      final File file = File('${temporary.path}/${output.key}');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(output.value, flush: true);
    }
    final String dartPath =
        '${temporary.path}/lib/src/c0_config_contract.g.dart';
    final ProcessResult formatted = Process.runSync(
      Platform.resolvedExecutable,
      <String>['format', dartPath],
    );
    _expect(
      formatted.exitCode == 0,
      'dart format failed: ${formatted.stdout}${formatted.stderr}',
    );

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
        ? 'C0 Config projection matches the authenticated release'
        : 'generated C0 Config projection from the authenticated release',
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

String _dartString(String value) => jsonEncode(value);

String _dartStringList(List<String> values) =>
    '<String>[${values.map(_dartString).join(',')}]';

String _dartLiteral(Object? value) {
  if (value is String) {
    return _dartString(value);
  }
  if (value is int || value is bool) {
    return value.toString();
  }
  if (value == null) {
    return 'null';
  }
  if (value is List<Object?>) {
    return '<Object?>[${value.map(_dartLiteral).join(',')}]';
  }
  if (value is Map<String, Object?>) {
    final List<String> keys = value.keys.toList()..sort();
    return '<String,Object?>{${keys.map((String key) => '${_dartString(key)}:${_dartLiteral(value[key])}').join(',')}}';
  }
  throw FormatException('unsupported Dart literal value: $value');
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
  const _Release({required this.manifest, required this.digest});

  final Map<String, Object?> manifest;
  final String digest;
}
