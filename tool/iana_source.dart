import 'dart:io';

/// Deterministic extraction of IANA timezone identifiers from the vendored
/// official native source files (see `third_party/iana-tzdata-<release>/`).
///
/// This is the single source of truth shared by `gen_iana_zones.dart` (which
/// writes `lib/src/iana_zones.dart`) and the stale-source detection test
/// (which regenerates and compares). It reads ONLY the committed, digest-pinned
/// native files — never `/usr/share/zoneinfo` or any host-derived artifact.

/// The zone-defining files of the standard (non-`backzone`) distribution, in
/// the fixed policy order. The identifier set is the union of every `Zone` and
/// `Link` declared here. `backzone` is excluded: it extends pre-1970 history of
/// existing zones and introduces no new identifier.
const List<String> ianaZoneDefiningFiles = <String>[
  'africa',
  'antarctica',
  'asia',
  'australasia',
  'europe',
  'northamerica',
  'southamerica',
  'etcetera',
  'factory',
  'backward',
];

/// The extracted release string and sorted, unique identifier union.
class IanaSource {
  const IanaSource({required this.release, required this.identifiers});

  final String release;
  final List<String> identifiers;
}

/// Extracts the release (`version` file) and the sorted identifier union from
/// the vendored native IANA source directory [sourceDir].
///
/// Throws [ArgumentError] if the directory or any required file is missing.
IanaSource extractIanaSource(String sourceDir) {
  if (!Directory(sourceDir).existsSync()) {
    throw ArgumentError('IANA source directory not found: $sourceDir');
  }
  final File versionFile = File('$sourceDir/version');
  if (!versionFile.existsSync()) {
    throw ArgumentError('missing version file in $sourceDir');
  }
  final String release = versionFile.readAsStringSync().trim();

  final Set<String> ids = <String>{};
  for (final String name in ianaZoneDefiningFiles) {
    final File file = File('$sourceDir/$name');
    if (!file.existsSync()) {
      throw ArgumentError('missing IANA source file: $sourceDir/$name');
    }
    for (final String line in file.readAsLinesSync()) {
      final List<String> fields = line.split(RegExp(r'\s+'));
      if (fields.isEmpty) {
        continue;
      }
      // Native files use full keywords with tab-separated fields:
      // `Zone <name> ...` and `Link <target> <link-name> [# comment]`.
      // Continuation lines of a zone are indented, so `^Zone`/`^Link` match
      // only the declaring line.
      switch (fields.first) {
        case 'Zone':
          if (fields.length >= 2) {
            ids.add(fields[1]);
          }
        case 'Link':
          if (fields.length >= 3) {
            ids.add(fields[2]);
          }
      }
    }
  }

  final List<String> sorted = ids.toList()..sort();
  return IanaSource(release: release, identifiers: sorted);
}
