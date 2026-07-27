/// Faro initialization port (argon feature port 1 of 5).
///
/// Stands ON TOP of `lib/integration/observability_wiring.dart`: that file owns
/// the LPSM label model ([ObservabilityLabels]) and the signal transport seam
/// ([SignalSink]). This file owns the *initialization* half — turning a projected
/// LPSM label set plus a [FaroConfig] into a live [FaroSession] whose sink can be
/// handed to an `ObservabilityContext`.
///
/// The concrete Grafana Faro SDK is deliberately NOT imported. Initialization is
/// expressed against the [FaroTransport] seam so that:
///
/// * the port is unit-testable without a collector or a platform channel, and
/// * init is *observable* — a test asserts the exact attribute map that was
///   pushed to the transport, so breaking the wiring (dropping a label, skipping
///   the transport call, mis-deriving an app-meta key) turns the gate RED.
///
/// Every entry point is a total function returning [Result]; nothing here throws
/// for an expected failure (disabled, incomplete identity, transport error).
library;

import '../core/result.dart';
import '../integration/observability_wiring.dart';

/// Grafana Faro app-meta attribute keys.
///
/// Faro's collector keys its app metadata on these names; the LPSM labels are
/// sent alongside them (never instead of them) so client signals join the same
/// LPSM cardinality as the backend services while still being addressable by a
/// stock Faro dashboard.
abstract final class FaroAttributeKeys {
  static const String appName = 'app_name';
  static const String appNamespace = 'app_namespace';
  static const String appVersion = 'app_version';
  static const String appEnvironment = 'app_environment';
  static const String appPlatform = 'app_platform';
}

/// Problem type URNs emitted by this port.
abstract final class FaroProblemTypes {
  static const String disabled = 'urn:diene:problem:faro-disabled';
  static const String incompleteIdentity =
      'urn:diene:problem:faro-identity-incomplete';
  static const String initFailed = 'urn:diene:problem:faro-init-failed';
}

/// The Faro SDK seam.
///
/// The real implementation lands with the accepted telemetry surface (see
/// [heldSignalTransportReason]); until then the app wires a
/// [RecordingFaroTransport]-free no-op and tests wire a recorder.
abstract interface class FaroTransport {
  /// Initialise the Faro client against [collectorUrl] with [attributes].
  ///
  /// Implementations must be safe to call at most once per process; the
  /// initializer calls it exactly once per successful [FaroInitializer.initialize].
  Future<void> initialize({
    required Uri collectorUrl,
    required Map<String, String> attributes,
    String? apiKey,
  });

  /// Push a measurement carrying the session [attributes] merged with any
  /// per-call extras.
  void pushMeasurement(String name, {required Map<String, String> attributes});
}

/// A [FaroTransport] that drops everything, for builds with no collector.
final class NoopFaroTransport implements FaroTransport {
  const NoopFaroTransport();

  @override
  Future<void> initialize({
    required Uri collectorUrl,
    required Map<String, String> attributes,
    String? apiKey,
  }) async {
    // Intentionally empty: no collector is configured.
  }

  @override
  void pushMeasurement(String name, {required Map<String, String> attributes}) {
    // Intentionally empty.
  }
}

/// Static configuration for the Faro client.
///
/// Carried as its own value (rather than read from `AppConfig`) so the port is
/// independent of the config surface that the lib/dart swap-in will replace.
final class FaroConfig {
  const FaroConfig({
    required this.collectorUrl,
    this.apiKey,
    this.enabled = true,
  });

  /// Faro collector endpoint.
  final Uri collectorUrl;

  /// Optional collector API key.
  final String? apiKey;

  /// Whether telemetry is switched on for this build/landscape.
  final bool enabled;
}

/// A live Faro session: the attribute map that was pushed at init, plus the
/// [SignalSink] that carries it onto every subsequent signal.
final class FaroSession {
  const FaroSession({
    required this.collectorUrl,
    required this.labels,
    required this.attributes,
    required this.sink,
  });

  /// Collector the session initialised against.
  final Uri collectorUrl;

  /// The LPSM labels bound to this session.
  final ObservabilityLabels labels;

  /// The exact attribute map handed to [FaroTransport.initialize].
  ///
  /// Exposed so callers (and the gate test) can assert on what init actually
  /// fired with rather than on the fact that it returned.
  final Map<String, String> attributes;

  /// Sink that pushes measurements through the initialised transport.
  final SignalSink sink;
}

/// Pushes measurements through an initialised [FaroTransport], stamping the
/// session attributes on every call.
final class FaroSignalSink implements SignalSink {
  const FaroSignalSink({required this.transport, required this.attributes});

  final FaroTransport transport;

  /// Session attributes stamped onto every measurement.
  final Map<String, String> attributes;

  @override
  void recordSignal(String name, {required Map<String, String> labels}) {
    transport.pushMeasurement(
      name,
      attributes: <String, String>{...labels, ...attributes},
    );
  }
}

/// Initialises Faro from a projected LPSM label set.
///
/// Stateless and constructor-injected: the transport is the only collaborator,
/// so a test substitutes a recorder and asserts on the pushed attributes.
final class FaroInitializer {
  const FaroInitializer({required this.transport, required this.config});

  final FaroTransport transport;
  final FaroConfig config;

  /// Derive the full Faro attribute map from an LPSM label set.
  ///
  /// LPSM labels come first (so the label map is a strict subset of the
  /// attributes), then the Faro app-meta keys derived from them. Ordering is
  /// deterministic for byte-identical dashboards.
  static Map<String, String> attributesFor(ObservabilityLabels labels) =>
      <String, String>{
        ...labels.toLabelMap(),
        FaroAttributeKeys.appName: labels.module,
        FaroAttributeKeys.appNamespace: labels.service,
        FaroAttributeKeys.appVersion: labels.version,
        FaroAttributeKeys.appEnvironment: labels.landscape,
        FaroAttributeKeys.appPlatform: labels.platform,
      };

  /// Initialise Faro for [labels].
  ///
  /// Returns:
  /// * `Failure` [FaroProblemTypes.disabled] when telemetry is switched off —
  ///   recoverable, because the app runs fine without a collector;
  /// * `Failure` [FaroProblemTypes.incompleteIdentity] when any LPSM label is
  ///   blank — an incomplete label set would poison LPSM cardinality, so it is
  ///   refused before the transport is touched;
  /// * `Failure` [FaroProblemTypes.initFailed] when the transport throws;
  /// * `Success` with the [FaroSession] otherwise.
  Future<Result<FaroSession>> initialize(ObservabilityLabels labels) async {
    if (!config.enabled) {
      return const Failure<FaroSession>(
        Problem(
          type: FaroProblemTypes.disabled,
          title: 'Telemetry disabled',
          status: 412,
          detail: 'Faro is disabled for this build; no collector was contacted.',
          recoverable: true,
        ),
      );
    }

    final List<String> missing = _blankLabelKeys(labels);
    if (missing.isNotEmpty) {
      return Failure<FaroSession>(
        Problem(
          type: FaroProblemTypes.incompleteIdentity,
          title: 'Incomplete observability identity',
          status: 500,
          detail:
              'Faro init refused: blank LPSM label(s) ${missing.join(', ')}.',
          data: <String, Object?>{'missing': missing},
        ),
      );
    }

    final Map<String, String> attributes = attributesFor(labels);
    try {
      await transport.initialize(
        collectorUrl: config.collectorUrl,
        attributes: attributes,
        apiKey: config.apiKey,
      );
    } on Object catch (error) {
      return Failure<FaroSession>(
        Problem(
          type: FaroProblemTypes.initFailed,
          title: 'Faro initialization failed',
          status: 500,
          detail: error.toString(),
          data: <String, Object?>{
            'collector': config.collectorUrl.toString(),
          },
        ),
      );
    }

    return Success<FaroSession>(
      FaroSession(
        collectorUrl: config.collectorUrl,
        labels: labels,
        attributes: attributes,
        sink: FaroSignalSink(transport: transport, attributes: attributes),
      ),
    );
  }

  static List<String> _blankLabelKeys(ObservabilityLabels labels) => labels
      .toLabelMap()
      .entries
      .where((MapEntry<String, String> entry) => entry.value.trim().isEmpty)
      .map((MapEntry<String, String> entry) => entry.key)
      .toList(growable: false);
}
