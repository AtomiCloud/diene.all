import 'dart:io';

/// Regenerates `lib/src/iana_zones.dart` from the authoritative IANA tz
/// database source (`tzdata.zi`, the `zic` input concatenation).
///
/// Provenance is mechanical: the complete set of valid IANA timezone
/// identifiers is exactly the union of every `Zone` name and every `Link`
/// (alias) name declared in the release. Nothing is hand-curated, so the
/// bundled allowlist is neither a partial handwritten list nor OS-local
/// runtime validation — it is a snapshot of one named IANA release baked into
/// the package for portable, deterministic validation.
///
/// Usage:
///   dart run tool/gen_iana_zones.dart [path-to-tzdata.zi]
///
/// The default source is the system-installed release at
/// `/usr/share/zoneinfo/tzdata.zi`. The release version is read from the
/// file's leading `# version <release>` line and stamped into the output.
void main(List<String> arguments) {
  if (arguments.length > 1) {
    stderr.writeln('usage: dart run tool/gen_iana_zones.dart [tzdata.zi]');
    exitCode = 64;
    return;
  }

  final String sourcePath =
      arguments.isEmpty ? '/usr/share/zoneinfo/tzdata.zi' : arguments.single;
  final File source = File(sourcePath);
  if (!source.existsSync()) {
    stderr.writeln('IANA tzdata source not found: $sourcePath');
    exitCode = 1;
    return;
  }

  final List<String> lines = source.readAsLinesSync();

  String release = 'unknown';
  final RegExp versionLine = RegExp(r'^#\s*version\s+(\S+)');
  for (final String line in lines) {
    final RegExpMatch? match = versionLine.firstMatch(line);
    if (match != null) {
      release = match.group(1)!;
      break;
    }
  }

  final Set<String> ids = <String>{};
  for (final String line in lines) {
    final List<String> fields = line.split(RegExp(r'\s+'));
    if (fields.isEmpty) {
      continue;
    }
    // `zic` input keywords are single-letter in the rearguard form:
    // `Z <name> ...` declares a Zone; `L <target> <link-name>` declares a Link
    // (an alias). Both names are valid IANA identifiers.
    switch (fields.first) {
      case 'Z':
      case 'Zone':
        if (fields.length >= 2) {
          ids.add(fields[1]);
        }
      case 'L':
      case 'Link':
        if (fields.length >= 3) {
          ids.add(fields[2]);
        }
    }
  }

  final List<String> sorted = ids.toList()..sort();

  final StringBuffer buffer = StringBuffer()
    ..writeln('// GENERATED FILE — DO NOT EDIT BY HAND.')
    ..writeln('//')
    ..writeln('// Source: IANA time zone database, release $release')
    ..writeln('//   (`tzdata.zi` Zone + Link records).')
    ..writeln('// Regenerate: dart run tool/gen_iana_zones.dart [tzdata.zi]')
    ..writeln('//')
    ..writeln('// The identifiers below are the union of every Zone name and')
    ..writeln('// every Link (alias) name in the release above. This is the')
    ..writeln('// authoritative, vetted allowlist used to validate C0 IANA')
    ..writeln('// timezone identifiers — not a handwritten subset and not')
    ..writeln('// OS-local runtime validation.')
    ..writeln('library;')
    ..writeln()
    ..writeln('/// The IANA release baked into [isIanaTimeZone].')
    ..writeln("const String ianaTimeZoneRelease = '$release';")
    ..writeln()
    ..writeln('/// Reports whether [id] is a valid IANA timezone identifier.')
    ..writeln('///')
    ..writeln('/// Membership is an exact, case-sensitive match against the')
    ..writeln('/// bundled IANA release [ianaTimeZoneRelease]. Offsets')
    ..writeln('/// (`+08:00`), bare abbreviations, and unknown names such as')
    ..writeln(
        '/// `Area/NotAnIanaZone` are rejected; canonical zones, aliases,')
    ..writeln('/// and the `UTC`/`Etc/*` forms are accepted.')
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
  for (final String id in sorted) {
    buffer.write('\n$id');
  }
  buffer.writeln("''';");

  final File output = File('lib/src/iana_zones.dart');
  output.writeAsStringSync(buffer.toString());
  stdout.writeln(
    'generated ${output.path}: ${sorted.length} identifiers '
    '(IANA release $release)',
  );
}
