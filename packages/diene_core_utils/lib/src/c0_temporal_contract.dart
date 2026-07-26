import 'iana_zones.dart';

/// The single, version-pinned C0 §1 temporal contract for the Dart family.
///
/// `diene_core_utils` OWNS this contract; every downstream Dart-family package
/// (config, problems, auth-engine, api-engine, e2e, interfaces) consumes the
/// SAME [c0TemporalContract] value — importing it via
/// `package:diene_core_utils/c0_temporal.dart` — instead of redefining its own
/// temporal cases. Its provenance pins the C0 source and the official IANA
/// release the timezone identifiers derive from, so conformance proofs never
/// read host IANA data or the host clock: timezone and clock vectors are
/// injected from this contract.
///
/// Stale-fixture detection: [C0TemporalProvenance.contentSha256] is a recorded
/// SHA-256 of [C0TemporalContract.digestPayload]; a test recomputes it and
/// fails if the vectors change without an intentional digest update, and also
/// asserts [C0TemporalProvenance.ianaRelease] equals the bundled
/// [ianaTimeZoneRelease].

/// Provenance for the shared C0 temporal contract.
final class C0TemporalProvenance {
  const C0TemporalProvenance({
    required this.contractVersion,
    required this.c0Section,
    required this.c0Source,
    required this.ianaRelease,
    required this.ianaArchiveUrl,
    required this.ianaArchiveSha256,
    required this.contentSha256,
  });

  /// Monotonic version of this contract's vectors.
  final String contractVersion;

  /// The binding C0 section (e.g. `C0 §1 Serialization`).
  final String c0Section;

  /// The C0 document the vectors are derived from.
  final String c0Source;

  /// The pinned IANA release the timezone identifiers derive from.
  final String ianaRelease;

  /// The official IANA archive URL for [ianaRelease].
  final String ianaArchiveUrl;

  /// The SHA-256 of the official IANA archive at [ianaArchiveUrl].
  final String ianaArchiveSha256;

  /// Recorded SHA-256 of [C0TemporalContract.digestPayload] (stale detection).
  final String contentSha256;
}

/// A deterministic instant-normalization vector: [input] (any RFC 3339 form,
/// including offsets) formats to [canonicalUtc] (RFC 3339 UTC `Z`). The instant
/// is injected — no host clock is read.
final class C0InstantVector {
  const C0InstantVector({required this.input, required this.canonicalUtc});

  final String input;
  final String canonicalUtc;
}

/// Positive/negative string cases for one temporal domain.
final class C0Cases {
  const C0Cases({required this.valid, required this.invalid});

  final List<String> valid;
  final List<String> invalid;
}

/// The version-pinned C0 temporal contract value.
final class C0TemporalContract {
  const C0TemporalContract({
    required this.provenance,
    required this.dates,
    required this.times,
    required this.durations,
    required this.timezones,
    required this.instants,
    required this.invalidInstants,
  });

  final C0TemporalProvenance provenance;
  final C0Cases dates;
  final C0Cases times;
  final C0Cases durations;

  /// Timezone identifier cases. `valid` deliberately includes legacy
  /// IANA-defined short identifiers (`EST`, `GMT`) and an alias (`US/Eastern`)
  /// alongside canonical zones; `invalid` includes the non-IANA abbreviation
  /// `PST`, offsets, wrong case, and path traversal. This settles the legacy-id
  /// question from the contract itself, not from host membership.
  final C0Cases timezones;

  /// Valid instant-normalization vectors (formatter, clock injected).
  final List<C0InstantVector> instants;

  /// Instant strings the strict RFC 3339 UTC parser must reject.
  final List<String> invalidInstants;

  /// Deterministic serialization hashed for stale-fixture detection. The order
  /// and separators are fixed; changing any vector changes this payload.
  String digestPayload() {
    final StringBuffer buffer = StringBuffer()
      ..writeln('contract=${provenance.contractVersion}')
      ..writeln('c0=${provenance.c0Section}|${provenance.c0Source}')
      ..writeln(
        'iana=${provenance.ianaRelease}|${provenance.ianaArchiveSha256}',
      )
      ..writeln('dates.valid=${dates.valid.join(",")}')
      ..writeln('dates.invalid=${dates.invalid.join(",")}')
      ..writeln('times.valid=${times.valid.join(",")}')
      ..writeln('times.invalid=${times.invalid.join(",")}')
      ..writeln('durations.valid=${durations.valid.join(",")}')
      ..writeln('durations.invalid=${durations.invalid.join(",")}')
      ..writeln('timezones.valid=${timezones.valid.join(",")}')
      ..writeln('timezones.invalid=${timezones.invalid.join(",")}')
      ..writeln(
        'instants=${instants.map((C0InstantVector v) => "${v.input}>${v.canonicalUtc}").join(",")}',
      )
      ..writeln('invalidInstants=${invalidInstants.join(",")}');
    return buffer.toString();
  }
}

/// The shared C0 temporal contract consumed unchanged across the Dart family.
const C0TemporalContract c0TemporalContract = C0TemporalContract(
  provenance: C0TemporalProvenance(
    contractVersion: '1',
    c0Section: 'C0 §1 Serialization',
    c0Source: 'goals/c0-contracts.md',
    ianaRelease: '2026b',
    ianaArchiveUrl:
        'https://data.iana.org/time-zones/releases/tzdata2026b.tar.gz',
    ianaArchiveSha256:
        '114543d9f19a6bfeb5bca43686aea173d38755a3db1f2eec112647ae92c6f544',
    contentSha256:
        'ca9f7cdb6f7c77007e02c59efb19d82e8c3e9553f6209041fa111fc02f7e1027',
  ),
  dates: C0Cases(
    valid: <String>['2026-07-21', '2000-02-29', '0001-01-01', '9999-12-31'],
    invalid: <String>[
      '21-07-2026',
      '2026-02-30',
      '2026-13-01',
      '2026-7-1',
      '2026/07/21',
    ],
  ),
  times: C0Cases(
    valid: <String>['00:00:00', '01:02:03', '23:59:59'],
    invalid: <String>['24:00:00', '01:60:00', '01:02:60', '1:02:03', '01:02'],
  ),
  durations: C0Cases(
    valid: <String>['P1DT2H3M4.5S', 'PT0.5S', 'P1Y2M3DT4H5M6S', 'P1W'],
    invalid: <String>['10 minutes', 'P', 'PT', '1DT2H', 'P1H'],
  ),
  timezones: C0Cases(
    valid: <String>[
      'Asia/Singapore',
      'America/Argentina/Buenos_Aires',
      'Etc/UTC',
      'UTC',
      'US/Eastern',
      'EST',
      'GMT',
    ],
    invalid: <String>[
      'Area/NotAnIanaZone',
      '+08:00',
      'asia/singapore',
      'Area/../Location',
      'PST',
      '',
    ],
  ),
  instants: <C0InstantVector>[
    C0InstantVector(
      input: '2026-07-21T09:02:03+08:00',
      canonicalUtc: '2026-07-21T01:02:03.000Z',
    ),
    C0InstantVector(
      input: '2026-07-21T01:02:03Z',
      canonicalUtc: '2026-07-21T01:02:03.000Z',
    ),
    C0InstantVector(
      input: '2026-07-21T01:02:03.456Z',
      canonicalUtc: '2026-07-21T01:02:03.456Z',
    ),
  ],
  invalidInstants: <String>[
    '2026-07-21T01:02:03+00:00',
    '2026-07-21T01:02:03+08:00',
    '2026-07-21T01:02:03',
    '2026-02-30T01:02:03Z',
    '2026-07-21 01:02:03Z',
  ],
);
