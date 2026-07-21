import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diene_config/c0_config.dart';
import 'package:test/test.dart';

const String _c0 = 'contracts/c0';
const String _domain = 'atomicloud.diene.c0-fixtures.release.v1';
const List<String> _policyPaths = <String>[
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

void main() {
  group('C0 release authentication independent of the generator', () {
    test('validates schema, bytes, sums, digest, and provenance in order', () {
      final File manifestFile = File('$_c0/RELEASE.json');
      final List<int> manifestBytes = manifestFile.readAsBytesSync();
      final Map<String, Object?> manifest = _object(
        jsonDecode(utf8.decode(manifestBytes, allowMalformed: false)),
      );

      // Schema validation is deliberately first.
      _validateManifest(manifest);

      expect(
        manifestBytes,
        utf8.encode('${jsonEncode(_sorted(manifest))}\n'),
        reason: 'RELEASE.json must be compact-canonical',
      );

      final Map<String, Object?> policy = _object(manifest['formatterPolicy']);
      final File policyFile = File(policy['path']! as String);
      final List<int> policyBytes = policyFile.readAsBytesSync();
      expect(sha256.convert(policyBytes).toString(), policy['sha256']);
      expect(utf8.decode(policyBytes), '${_policyPaths.join('\n')}\n');

      final List<int> sumsBytes = File('$_c0/SHA256SUMS').readAsBytesSync();
      final Map<String, String> sums = _strictSums(
        sumsBytes,
        pathPattern: RegExp(
          r'^(README[.]md|cases/[^/]+[.]json|provenance/[^/]+[.]md)$',
        ),
      );
      final List<String> expectedCoverage = <String>[
        'README.md',
        ..._files('cases', '.json'),
        ..._files('provenance', '.md'),
      ]..sort();
      expect(sums.keys.toList(), expectedCoverage);
      for (final MapEntry<String, String> sum in sums.entries) {
        expect(
          sha256.convert(File('$_c0/${sum.key}').readAsBytesSync()).toString(),
          sum.value,
          reason: 'release sum mismatch for ${sum.key}',
        );
      }

      final Map<String, Object?> payloadManifest = Map<String, Object?>.of(
        manifest,
      )..remove('releaseDigest');
      final List<int> payload = <int>[
        ...utf8.encode('$_domain\n'),
        ...utf8.encode('${jsonEncode(_sorted(payloadManifest))}\n'),
        ...sumsBytes,
      ];
      final String digest = sha256.convert(payload).toString();
      expect(digest, manifest['releaseDigest']);
      expect(c0ConfigContract.provenance.releaseId, manifest['releaseId']);
      expect(
        c0ConfigContract.provenance.contractVersion,
        manifest['contractVersion'],
      );
      expect(c0ConfigContract.provenance.releaseDigest, digest);
      expect(
        c0ConfigContract.provenance.c0ProseSource.path,
        _object(manifest['c0ProseSource'])['path'],
      );
      expect(
        c0ConfigContract.provenance.c0ProseSource.sha256,
        _object(manifest['c0ProseSource'])['sha256'],
      );
      expect(
        c0ConfigContract.provenance.formatterPolicySha256,
        policy['sha256'],
      );
      expect(
        c0ConfigContract.provenance.prettierExcludedPaths,
        policy['prettierExcludedPaths'],
      );
    });

    test('both neutral case files have strict shape and canonical bytes', () {
      for (final String name in <String>['config.json', 'problem.json']) {
        final File file = File('$_c0/cases/$name');
        final List<int> bytes = file.readAsBytesSync();
        final Map<String, Object?> value = _object(
          jsonDecode(utf8.decode(bytes, allowMalformed: false)),
        );
        _validateCase(value);
        expect(
          bytes,
          utf8.encode(
            '${const JsonEncoder.withIndent('  ').convert(_sorted(value))}\n',
          ),
          reason: '$name must be pretty-canonical',
        );
      }
    });

    test('generated JSON bytes and checksums are deterministic', () {
      final Map<String, String> sums = _strictSums(
        File('test/fixtures/c0/SHA256SUMS').readAsBytesSync(),
        pathPattern: RegExp(r'^[a-z0-9-]+[.]json$'),
      );
      expect(sums.keys, <String>['config.json']);
      for (final MapEntry<String, String> sum in sums.entries) {
        final File file = File('test/fixtures/c0/${sum.key}');
        final List<int> bytes = file.readAsBytesSync();
        final Map<String, Object?> value = _object(
          jsonDecode(utf8.decode(bytes)),
        );
        expect(sha256.convert(bytes).toString(), sum.value);
        expect(
          bytes,
          utf8.encode(
            '${const JsonEncoder.withIndent('  ').convert(_sorted(value))}\n',
          ),
        );
      }
    });

    test('strict schema rejects unknown top-level and nested keys', () {
      final Map<String, Object?> original = _object(
        jsonDecode(File('$_c0/RELEASE.json').readAsStringSync()),
      );
      final Map<String, Object?> topLevel = _clone(original)..['extra'] = 1;
      expect(() => _validateManifest(topLevel), throwsFormatException);

      final Map<String, Object?> nested = _clone(original);
      nested['c0ProseSource'] = _object(nested['c0ProseSource'])..['extra'] = 1;
      expect(() => _validateManifest(nested), throwsFormatException);
    });
  });
}

void _validateManifest(Map<String, Object?> value) {
  _keys(value, <String>{
    'releaseId',
    'contractVersion',
    'releaseDigest',
    'domains',
    'c0ProseSource',
    'secondarySources',
    'formatterPolicy',
  });
  _manifestValues(value);
  final RegExpMatch? id = RegExp(
    r'^c0-fixtures-r([1-9][0-9]*)$',
  ).firstMatch(value['releaseId']! as String);
  if (id == null ||
      value['contractVersion'] is! int ||
      int.parse(id.group(1)!) != value['contractVersion']) {
    throw const FormatException('releaseId/version mismatch');
  }
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value['releaseDigest']! as String)) {
    throw const FormatException('invalid release digest');
  }
  if (jsonEncode(value['domains']) !=
      jsonEncode(<String>['config', 'problem'])) {
    throw const FormatException('invalid domains');
  }

  final Map<String, Object?> source = _object(value['c0ProseSource']);
  _keys(source, <String>{'path', 'sha256', 'note'});
  if (source['path'] != 'goals/c0-contracts.md' ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(source['sha256']! as String) ||
      (source['note']! as String).isEmpty) {
    throw const FormatException('invalid C0 source');
  }

  final List<Object?> secondary = _array(value['secondarySources']);
  if (secondary.length != 1) {
    throw const FormatException('invalid secondary sources');
  }
  final Map<String, Object?> dart = _object(secondary.single);
  _keys(dart, <String>{'path', 'sha256'});
  if (dart['path'] != 'goals/lib/dart-family.md' ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(dart['sha256']! as String)) {
    throw const FormatException('invalid Dart-family source');
  }

  final Map<String, Object?> policy = _object(value['formatterPolicy']);
  _keys(policy, <String>{'path', 'prettierExcludedPaths', 'sha256'});
  if (policy['path'] != '.prettierignore' ||
      jsonEncode(policy['prettierExcludedPaths']) != jsonEncode(_policyPaths) ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(policy['sha256']! as String)) {
    throw const FormatException('invalid formatter policy');
  }
}

void _manifestValues(Object? value) {
  if (value is String) {
    if (!value.runes.every(
      (int rune) =>
          rune >= 0x20 && rune <= 0x7e && rune != 0x22 && rune != 0x5c,
    )) {
      throw const FormatException('unsafe manifest string');
    }
    return;
  }
  if (value == null || value is bool || value is int) {
    return;
  }
  if (value is num) {
    throw const FormatException('non-integer manifest number');
  }
  if (value is List<dynamic>) {
    value.forEach(_manifestValues);
    return;
  }
  if (value is Map<String, dynamic>) {
    value.values.forEach(_manifestValues);
    return;
  }
  throw const FormatException('unsupported manifest value');
}

void _validateCase(Map<String, Object?> value) {
  _keys(value, <String>{'domain', 'c0Sections', 'cases'});
  _caseValues(value);
  final Map<String, Object?> cases = _object(value['cases']);
  if (value['domain'] == 'problem') {
    if (jsonEncode(value['c0Sections']) !=
        jsonEncode(<String>[
          '§2 Problem schema',
          '§14 Problem catalog schema',
        ])) {
      throw const FormatException('invalid Problem sections');
    }
    _keys(cases, <String>{
      'rfc9457Members',
      'extensions',
      'typeUriTemplate',
      'typeUri',
      'envelopes',
      'catalogEntry',
    });
  } else if (value['domain'] == 'config') {
    if (jsonEncode(value['c0Sections']) !=
        jsonEncode(<String>['§3 Config precedence'])) {
      throw const FormatException('invalid Config sections');
    }
    _keys(cases, <String>{
      'layeringAndIndexedList',
      'blankIsUnset',
      'noJsonNoComma',
      'caseInsensitiveKeyMatching',
      'finalLayerValidation',
    });
  } else {
    throw const FormatException('invalid case domain');
  }
}

void _caseValues(Object? value) {
  if (value == null || value is bool || value is String || value is int) {
    return;
  }
  if (value is num) {
    throw const FormatException('non-integer case number');
  }
  if (value is List<dynamic>) {
    value.forEach(_caseValues);
    return;
  }
  if (value is Map<String, dynamic>) {
    for (final MapEntry<String, dynamic> entry in value.entries) {
      if (!entry.key.runes.every(
        (int rune) =>
            rune >= 0x20 && rune <= 0x7e && rune != 0x22 && rune != 0x5c,
      )) {
        throw const FormatException('unsafe case key');
      }
      _caseValues(entry.value);
    }
    return;
  }
  throw const FormatException('unsupported case value');
}

Map<String, String> _strictSums(List<int> bytes, {RegExp? pathPattern}) {
  if (bytes.isEmpty || bytes.last != 10 || bytes.contains(13)) {
    throw const FormatException('invalid sums line endings');
  }
  final List<String> lines = utf8
      .decode(bytes, allowMalformed: false)
      .substring(0, bytes.length - 1)
      .split('\n');
  final RegExp grammar = RegExp(r'^([0-9a-f]{64})  (.+)$');
  final Map<String, String> result = <String, String>{};
  for (final String line in lines) {
    final RegExpMatch? match = grammar.firstMatch(line);
    if (match == null || line.isEmpty) {
      throw FormatException('malformed sum: $line');
    }
    final String path = match.group(2)!;
    if (pathPattern != null && !pathPattern.hasMatch(path)) {
      throw FormatException('invalid sum path: $path');
    }
    if (result.containsKey(path)) {
      throw FormatException('duplicate sum path: $path');
    }
    result[path] = match.group(1)!;
  }
  final List<String> sorted = result.keys.toList()..sort();
  if (jsonEncode(sorted) != jsonEncode(result.keys.toList())) {
    throw const FormatException('unsorted sums');
  }
  return result;
}

List<String> _files(String directory, String extension) =>
    Directory('$_c0/$directory')
        .listSync(followLinks: false)
        .whereType<File>()
        .map((File file) => file.path.substring('$_c0/'.length))
        .where((String path) => path.endsWith(extension))
        .toList(growable: false);

Object? _sorted(Object? value) {
  if (value is Map<String, dynamic>) {
    final List<String> keys = value.keys.toList()..sort();
    return <String, Object?>{
      for (final String key in keys) key: _sorted(value[key]),
    };
  }
  if (value is List<dynamic>) {
    return value.map<Object?>(_sorted).toList(growable: false);
  }
  return value;
}

void _keys(Map<String, Object?> value, Set<String> expected) {
  final Set<String> actual = value.keys.toSet();
  if (actual.length != expected.length || !actual.containsAll(expected)) {
    throw FormatException('unknown or missing keys: $actual != $expected');
  }
}

Map<String, Object?> _object(Object? value) =>
    Map<String, Object?>.from(value! as Map<dynamic, dynamic>);

List<Object?> _array(Object? value) =>
    List<Object?>.from(value! as List<dynamic>);

Map<String, Object?> _clone(Map<String, Object?> value) =>
    _object(jsonDecode(jsonEncode(value)));
