/// E4-final observability wiring — stands on flutter-base `891c5c9…` + the
/// `observability` payload (state: done).
///
/// This is the ONE part of the E4-final integration that genuinely stands today:
/// it needs only the frozen flutter-base app shell (for [AppIdentityConfig]) and
/// the observability payload's **LPSM label model** (landscape / platform /
/// service / module). It does NOT depend on `lib/dart/e2e`, so it is scaffolded
/// live rather than held.
///
/// The observability standard requires every emitted signal (metric / log /
/// trace) to carry the four LPSM labels projected from the service tree. Here
/// those labels are projected from the app's own [AppIdentityConfig] so the
/// Flutter client emits signals that join the same LPSM cardinality as the
/// backend services.
///
/// The concrete signal transport (OTel / Grafana Faro exporter) is the seam that
/// lands with the accepted `lib/dart/e2e` telemetry surface — see
/// [SignalSink] / [heldSignalTransportReason]. Until then a [NoopSignalSink]
/// keeps the app buildable and runnable without a live exporter.
library;

import '../config/app_config.dart';

/// Canonical LPSM label keys mandated by the observability payload standard.
///
/// Kept as string constants (not an enum) so they serialise directly into the
/// label maps consumed by Prometheus/Loki/Tempo exporters without a lookup.
abstract final class ObservabilityLabelKeys {
  static const String landscape = 'landscape';
  static const String platform = 'platform';
  static const String service = 'service';
  static const String module = 'module';
  static const String version = 'version';
}

/// An immutable projection of the LPSM label set for this client.
///
/// Constructed from plain strings (pure-Dart testable) or from the app's
/// [AppIdentityConfig] via [ObservabilityLabels.fromIdentity].
final class ObservabilityLabels {
  const ObservabilityLabels({
    required this.landscape,
    required this.platform,
    required this.service,
    required this.module,
    required this.version,
  });

  /// Project the LPSM label set from the app identity carried by
  /// [AppIdentityConfig], the same identity the app already loads at startup.
  factory ObservabilityLabels.fromIdentity(AppIdentityConfig identity) =>
      ObservabilityLabels(
        landscape: identity.landscape,
        platform: identity.platform,
        service: identity.service,
        module: identity.module,
        version: identity.version,
      );

  final String landscape;
  final String platform;
  final String service;
  final String module;
  final String version;

  /// The canonical label map applied to every signal from this client.
  ///
  /// Ordering is deterministic (LPSM, then version) so equal label sets render
  /// to byte-identical maps for dashboard/alert cardinality stability.
  Map<String, String> toLabelMap() => <String, String>{
    ObservabilityLabelKeys.landscape: landscape,
    ObservabilityLabelKeys.platform: platform,
    ObservabilityLabelKeys.service: service,
    ObservabilityLabelKeys.module: module,
    ObservabilityLabelKeys.version: version,
  };

  @override
  bool operator ==(Object other) =>
      other is ObservabilityLabels &&
      other.landscape == landscape &&
      other.platform == platform &&
      other.service == service &&
      other.module == module &&
      other.version == version;

  @override
  int get hashCode =>
      Object.hash(landscape, platform, service, module, version);

  @override
  String toString() => 'ObservabilityLabels(${toLabelMap()})';
}

/// The transport seam a real OTel / Grafana Faro exporter will implement.
///
/// The concrete exporter arrives with the accepted `lib/dart/e2e` telemetry
/// surface; until then the app wires a [NoopSignalSink] so nothing crashes when
/// no exporter is configured.
abstract interface class SignalSink {
  /// Record a counter/gauge sample carrying the client's LPSM [labels].
  void recordSignal(String name, {required Map<String, String> labels});
}

/// Reason the concrete signal transport is held out of this scaffold.
///
/// Surfaced so callers/reviewers see the hold at the wiring seam itself rather
/// than only in the node status file.
const String heldSignalTransportReason =
    'Concrete OTel/Faro exporter lands with the accepted lib/dart/e2e telemetry '
    'surface (no accepted sha yet). SCAFFOLD holds a NoopSignalSink.';

/// Default no-op sink so the app builds and runs without a live exporter.
final class NoopSignalSink implements SignalSink {
  const NoopSignalSink();

  @override
  void recordSignal(String name, {required Map<String, String> labels}) {
    // Intentionally empty: no exporter is wired in the SCAFFOLD phase.
  }
}

/// The observability context handed to the app at startup.
///
/// Binds the projected LPSM [labels] to whichever [sink] is active. During the
/// SCAFFOLD phase the sink is a [NoopSignalSink]; the accepted-e2e integration
/// swaps in the real exporter without touching call sites.
final class ObservabilityContext {
  const ObservabilityContext({
    required this.labels,
    this.sink = const NoopSignalSink(),
  });

  /// Build the context from the app identity, defaulting to the no-op sink.
  factory ObservabilityContext.fromIdentity(
    AppIdentityConfig identity, {
    SignalSink sink = const NoopSignalSink(),
  }) => ObservabilityContext(
    labels: ObservabilityLabels.fromIdentity(identity),
    sink: sink,
  );

  final ObservabilityLabels labels;
  final SignalSink sink;

  /// Emit a signal named [name] with the bound LPSM labels merged with any
  /// per-call [extra] labels (call labels never override the LPSM base set).
  void emit(
    String name, {
    Map<String, String> extra = const <String, String>{},
  }) {
    final Map<String, String> merged = <String, String>{
      ...extra,
      ...labels.toLabelMap(),
    };
    sink.recordSignal(name, labels: merged);
  }
}
