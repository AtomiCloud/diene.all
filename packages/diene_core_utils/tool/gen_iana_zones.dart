import 'dart:io';

import 'iana_source.dart';

/// Regenerates (or verifies) `lib/src/iana_zones.dart` from the vendored
/// official IANA native source files.
///
/// Provenance is repository-owned and verifiable: the identifiers are the
/// union of every `Zone` and `Link` name declared in the digest-pinned native
/// files under `third_party/iana-tzdata-<release>/` (see that directory's
/// `PROVENANCE.md` and `SHA256SUMS`). This tool NEVER reads
/// `/usr/share/zoneinfo` or any host-derived `tzdata.zi`: there is no host
/// default, so proof generation cannot silently fall back to host data.
///
/// Usage:
///
/// ```
/// dart run tool/gen_iana_zones.dart --source <dir>          # write
/// dart run tool/gen_iana_zones.dart --source <dir> --check  # verify only
/// ```
///
/// `--check` regenerates in memory and compares byte-for-byte to the committed
/// `lib/src/iana_zones.dart`, exiting non-zero on any drift (stale-source
/// detection). The default `--source` is the vendored 2026b directory.
const String _defaultSource = '../../third_party/iana-tzdata-2026b';
const String _outputPath = 'lib/src/iana_zones.dart';

void main(List<String> arguments) {
  final List<String> args = List<String>.of(arguments);
  final bool check = args.remove('--check');
  String source = _defaultSource;
  final int sourceFlag = args.indexOf('--source');
  if (sourceFlag != -1) {
    if (sourceFlag + 1 >= args.length) {
      stderr.writeln('--source requires a directory argument');
      exitCode = 64;
      return;
    }
    source = args[sourceFlag + 1];
    args.removeRange(sourceFlag, sourceFlag + 2);
  }
  if (args.isNotEmpty) {
    stderr.writeln(
      'usage: dart run tool/gen_iana_zones.dart [--source <dir>] [--check]',
    );
    exitCode = 64;
    return;
  }

  final IanaSource extracted;
  try {
    extracted = extractIanaSource(source);
  } on ArgumentError catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
    return;
  }

  final String rendered = _render(extracted);

  if (check) {
    final File output = File(_outputPath);
    final String committed = output.existsSync()
        ? output.readAsStringSync()
        : '';
    if (committed != rendered) {
      stderr.writeln(
        'STALE: $_outputPath does not match regeneration from $source '
        '(IANA release ${extracted.release}, ${extracted.identifiers.length} '
        'identifiers). Run: dart run tool/gen_iana_zones.dart',
      );
      exitCode = 1;
      return;
    }
    stdout.writeln(
      'iana-zones check: $_outputPath matches $source '
      '(release ${extracted.release}, ${extracted.identifiers.length} ids)',
    );
    return;
  }

  File(_outputPath).writeAsStringSync(rendered);
  stdout.writeln(
    'generated $_outputPath: ${extracted.identifiers.length} identifiers '
    '(IANA release ${extracted.release}, source $source)',
  );
}

String _render(IanaSource source) {
  final StringBuffer buffer = StringBuffer()
    ..writeln('// GENERATED FILE — DO NOT EDIT BY HAND.')
    ..writeln('//')
    ..writeln('// Source: vendored official IANA time zone database, release')
    ..writeln('//   ${source.release} (Zone + Link records of the standard,')
    ..writeln('//   non-backzone distribution — see')
    ..writeln('//   third_party/iana-tzdata-${source.release}/PROVENANCE.md).')
    ..writeln('// Regenerate: dart run tool/gen_iana_zones.dart')
    ..writeln('// Verify:     dart run tool/gen_iana_zones.dart --check')
    ..writeln('//')
    ..writeln('// The allowlist is reproducible from the pinned official')
    ..writeln('// release, not from host `/usr/share/zoneinfo` data.')
    ..writeln('library;')
    ..writeln()
    ..writeln('/// The IANA release baked into [isIanaTimeZone].')
    ..writeln("const String ianaTimeZoneRelease = '${source.release}';")
    ..writeln()
    ..writeln('/// Reports whether [id] is a valid IANA timezone identifier.')
    ..writeln('///')
    ..writeln('/// Membership is an exact, case-sensitive match against the')
    ..writeln('/// vendored IANA release [ianaTimeZoneRelease]. Offsets')
    ..writeln('/// (`+08:00`), non-IANA abbreviations (`PST`), and unknown')
    ..writeln('/// names such as `Area/NotAnIanaZone` are rejected; canonical')
    ..writeln('/// zones, IANA aliases, the `Etc/*` family, and bare `UTC` are')
    ..writeln(
      '/// accepted. Legacy IANA-defined short identifiers (e.g. `EST`,',
    )
    ..writeln('/// `CET`) are genuine database entries and are accepted; the')
    ..writeln('/// C0 temporal contract fixes the settled cases.')
    ..writeln(
      'bool isIanaTimeZone(String id) => _ianaTimeZoneIds.contains(id);',
    )
    ..writeln()
    ..writeln('final Set<String> _ianaTimeZoneIds = _ianaTimeZoneData')
    ..writeln("    .split('\\n')")
    ..writeln('    .where((String line) => line.isNotEmpty)')
    ..writeln('    .toSet();')
    ..writeln()
    ..write("const String _ianaTimeZoneData = '''");
  for (final String id in source.identifiers) {
    buffer.write('\n$id');
  }
  buffer.writeln("''';");
  return buffer.toString();
}
