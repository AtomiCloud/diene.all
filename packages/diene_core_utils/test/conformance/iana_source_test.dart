import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:test/test.dart';

import '../../tool/iana_source.dart';

/// Enforced stale-source detection for the IANA timezone allowlist.
///
/// The runtime allowlist (`lib/src/iana_zones.dart`) must be reproducible from
/// the vendored, digest-pinned official IANA source at the repository root, NOT
/// from any host artifact such as `/usr/share/zoneinfo`. These checks fail if
/// the committed set drifts from the vendored source, if a vendored file is
/// tampered with, or if the release pins disagree.
///
/// The vendored source is COMMITTED, so its absence is a repository defect, not
/// a legitimate skip: an absent-source `markTestSkipped` would make every
/// assertion below unreachable while the suite still reported green — the
/// vacuous-gate shape. It therefore fails loudly instead. (Nothing runs these
/// tests from a published archive: `.pubignore` excludes `test/` and `tool/`.)
const String _sourceDir = '../../third_party/iana-tzdata-2026b';
const String _allowlistPath = 'lib/src/iana_zones.dart';

void main() {
  group('IANA source reproducibility', () {
    setUpAll(() {
      expect(
        Directory(_sourceDir).existsSync(),
        isTrue,
        reason:
            'vendored IANA source $_sourceDir is missing; it is committed and '
            'every check in this group depends on it',
      );
    });

    test('committed allowlist set equals the vendored-source extraction', () {
      final Set<String> extracted = extractIanaSource(
        _sourceDir,
      ).identifiers.toSet();
      final Set<String> committed = _committedAllowlistIds();

      // Assert on the VALUES, not merely on emptiness: a parser that silently
      // read nothing would make both differences empty and look green.
      expect(
        extracted.length,
        greaterThan(500),
        reason: 'extraction produced implausibly few identifiers',
      );
      expect(
        committed.length,
        extracted.length,
        reason:
            'allowlist has ${committed.length} ids, vendored source has '
            '${extracted.length}',
      );
      expect(
        committed.difference(extracted),
        isEmpty,
        reason: 'allowlist has identifiers not in the vendored source (stale)',
      );
      expect(
        extracted.difference(committed),
        isEmpty,
        reason: 'vendored source has identifiers missing from the allowlist',
      );

      // Behavioural tie: the exported predicate agrees with the committed set.
      for (final String id in <String>['Asia/Singapore', 'UTC', 'US/Eastern']) {
        expect(isIanaTimeZone(id), isTrue, reason: '$id must be accepted');
        expect(committed.contains(id), isTrue);
      }
      expect(isIanaTimeZone('Area/NotAnIanaZone'), isFalse);
    });

    test('release pins agree across source, runtime, and C0 contract', () {
      final String release = extractIanaSource(_sourceDir).release;
      expect(release, '2026b');
      expect(release, ianaTimeZoneRelease);
      expect(release, c0TemporalContract.provenance.ianaRelease);
    });

    test('vendored files match their recorded SHA-256 digests', () {
      final File sums = File('$_sourceDir/SHA256SUMS');
      expect(sums.existsSync(), isTrue, reason: 'missing SHA256SUMS');

      int verified = 0;
      final List<String> mismatches = <String>[];
      for (final String line in sums.readAsLinesSync()) {
        if (line.trim().isEmpty) {
          continue;
        }
        final Match? match = RegExp(
          r'^([0-9a-f]{64})\s+(.+)$',
        ).firstMatch(line);
        expect(match, isNotNull, reason: 'malformed SHA256SUMS line: $line');
        final String expected = match!.group(1)!;
        final String name = match.group(2)!;
        final File file = File('$_sourceDir/$name');
        if (!file.existsSync()) {
          mismatches.add('missing $name');
          continue;
        }
        final String actual = sha256.convert(file.readAsBytesSync()).toString();
        if (actual != expected) {
          mismatches.add('$name: $actual != $expected');
        }
        verified += 1;
      }

      // A digest ledger that verified ZERO files is indistinguishable from one
      // that never ran, so the count is asserted alongside the mismatches.
      expect(
        verified,
        greaterThanOrEqualTo(ianaZoneDefiningFiles.length + 1),
        reason:
            'verified only $verified files; expected at least the '
            '${ianaZoneDefiningFiles.length} zone-defining files plus version',
      );
      expect(mismatches, isEmpty, reason: 'digest mismatches: $mismatches');
    });

    test(
      'extraction rejects a missing directory and a missing member file',
      () {
        expect(
          () => extractIanaSource('$_sourceDir-does-not-exist'),
          throwsA(isA<ArgumentError>()),
        );

        final Directory partial = Directory.systemTemp.createTempSync(
          'iana-partial',
        );
        addTearDown(() => partial.deleteSync(recursive: true));
        expect(
          () => extractIanaSource(partial.path),
          throwsA(isA<ArgumentError>()),
          reason: 'a directory with no version file must be rejected',
        );
        File('${partial.path}/version').writeAsStringSync('2026b\n');
        expect(
          () => extractIanaSource(partial.path),
          throwsA(isA<ArgumentError>()),
          reason: 'a directory with no zone-defining files must be rejected',
        );
      },
    );
  });
}

/// Parses the identifier lines out of the generated allowlist file's
/// triple-quoted data block.
Set<String> _committedAllowlistIds() {
  final List<String> lines = File(_allowlistPath).readAsLinesSync();
  final Set<String> ids = <String>{};
  bool inData = false;
  for (final String raw in lines) {
    if (!inData) {
      if (raw.contains("_ianaTimeZoneData = '''")) {
        inData = true;
      }
      continue;
    }
    final String line = raw.replaceAll("''';", '').trim();
    if (line.isNotEmpty) {
      ids.add(line);
    }
    if (raw.contains("'''")) {
      break;
    }
  }
  return ids;
}
