/// The version-pinned identity of the C0 §3 release this package binds.
///
/// The VECTORS are not restated here — they live in the frozen release under
/// `contracts/c0/cases/config.json` and are projected into
/// `test/fixtures/c0/config.json` by `tool/gen_c0_projection.dart`. What this
/// contract carries is the release IDENTITY: which release, which digest, which
/// sections, and which vectors this package claims to bind.
///
/// Separating the two is what makes the conformance suite honest. The suite
/// reads the projection for its inputs and this value for its expectations, so
/// a projection regenerated from a DIFFERENT release fails the binding test
/// instead of silently passing against new vectors.
///
/// This mirrors how `diene_core_utils` exports its C0 §1 temporal contract:
/// one shared value, consumed rather than restated.
library;

/// Identity of the frozen C0 release a package binds its conformance to.
final class C0ConfigProvenance {
  /// Creates a release pin.
  const C0ConfigProvenance({
    required this.releaseId,
    required this.contractVersion,
    required this.releaseDigest,
    required this.sourceCase,
    required this.c0Sections,
  });

  /// Release identifier, e.g. `c0-fixtures-r2`.
  final String releaseId;

  /// Monotonic contract version embedded in [releaseId].
  final int contractVersion;

  /// Complete-release digest recorded in the release manifest.
  final String releaseDigest;

  /// Repository-relative path of the normative case file.
  final String sourceCase;

  /// The binding C0 sections.
  final List<String> c0Sections;
}

/// The C0 §3 contract `diene_config` binds.
final class C0ConfigContract {
  /// Creates a contract pin.
  const C0ConfigContract({
    required this.provenance,
    required this.projectedCases,
  });

  /// Which frozen release these vectors come from.
  final C0ConfigProvenance provenance;

  /// The §3 vectors this package binds, in projection order.
  ///
  /// `diene_config` binds ALL FIVE. `finalLayerValidation` is the one
  /// `diene_core_utils` deliberately omits, because validating the merged layer
  /// is this package's responsibility rather than that of the merge primitives
  /// it consumes.
  final List<String> projectedCases;
}

/// The single C0 §3 contract value for the Dart config package.
const C0ConfigContract c0ConfigContract = C0ConfigContract(
  provenance: C0ConfigProvenance(
    releaseId: 'c0-fixtures-r2',
    contractVersion: 2,
    releaseDigest:
        '0e64439c681a22fb4f02285c082ed8ffb7b465e732fde4e49757e9e3c9a5783e',
    sourceCase: 'contracts/c0/cases/config.json',
    c0Sections: <String>['§3 Config precedence'],
  ),
  projectedCases: <String>[
    'blankIsUnset',
    'caseInsensitiveKeyMatching',
    'finalLayerValidation',
    'layeringAndIndexedList',
    'noJsonNoComma',
  ],
);
