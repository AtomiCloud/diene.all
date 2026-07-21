import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:test/test.dart';

import '../tool/iana_source.dart';

/// Enforced stale-source detection for the IANA timezone allowlist.
///
/// The runtime allowlist (`lib/src/iana_zones.dart`) must be reproducible from
/// the vendored, digest-pinned official IANA source (`third_party/…`), NOT from
/// any host artifact. These checks fail if the committed set drifts from the
/// vendored source, if a vendored file is tampered with, or if the release pins
/// disagree.
///
/// The vendored source is a repository build input, not shipped in the pub
/// archive; when it is absent (running from a published archive) the checks
/// skip rather than fail.
const String _sourceDir = 'third_party/iana-tzdata-2026b';
const String _allowlistPath = 'lib/src/iana_zones.dart';

void main() {
  final bool sourcePresent = Directory(_sourceDir).existsSync();

  group('IANA source reproducibility', () {
    test('committed allowlist set equals the vendored-source extraction', () {
      if (!sourcePresent) {
        markTestSkipped('vendored IANA source absent (not in pub archive)');
        return;
      }
      final Set<String> extracted = extractIanaSource(
        _sourceDir,
      ).identifiers.toSet();
      final Set<String> committed = _committedAllowlistIds();

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
      // Behavioral tie: the exported predicate agrees with the committed set.
      for (final String id in <String>['Asia/Singapore', 'UTC', 'US/Eastern']) {
        expect(isIanaTimeZone(id), isTrue);
      }
    });

    test('release pins agree across source, runtime, and contract', () {
      if (!sourcePresent) {
        markTestSkipped('vendored IANA source absent');
        return;
      }
      final String release = extractIanaSource(_sourceDir).release;
      expect(release, ianaTimeZoneRelease);
      expect(release, c0TemporalContract.provenance.ianaRelease);
    });

    test('vendored files match their recorded SHA-256 digests', () {
      if (!sourcePresent) {
        markTestSkipped('vendored IANA source absent');
        return;
      }
      final File sums = File('$_sourceDir/SHA256SUMS');
      expect(sums.existsSync(), isTrue, reason: 'missing SHA256SUMS');
      final List<String> mismatches = <String>[];
      for (final String line in sums.readAsLinesSync()) {
        if (line.trim().isEmpty) {
          continue;
        }
        final Match? match =
            RegExp(r'^([0-9a-f]{64})\s+(.+)$').firstMatch(line);
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
      }
      expect(mismatches, isEmpty);
    });
  });
}

/// Parses the identifier lines out of the generated allowlist file's triple
/// quoted data block.
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
