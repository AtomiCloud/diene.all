/// Problem catalog EXPORT (C0 §14).
///
/// Each service publishes a `Problem` catalog CR (per service × landscape) whose
/// `problems[]` list declares every problem an endpoint can return:
/// `{ id, type, title, status, recoverable, data, endpoints[] }`. This file is
/// the PRODUCER side: it builds those entries (type URIs via the single-source
/// builder) and emits the per-row CR content that the service's primordial chart
/// renders and erbium merges into the edge error portal (ARCHITECTURE §4/§9).
///
/// Frontends classify recoverable-vs-fatal from the EDGE-PUBLISHED catalog —
/// never by calling Primordial — so the [CatalogEntry.recoverable] flag shipped
/// here is what the flutter error classifier (Problem visualizer) ultimately
/// reads.
///
/// There is NO runtime error-info surface here: runtime `/error-info` endpoints
/// are REPLACED by this catalog, not wrapped.
library;

import 'problem_type_uri.dart';
import 'registry.dart';

/// A method+path pair declaring which endpoint can return a problem.
final class CatalogEndpoint {
  /// Creates an endpoint declaration.
  const CatalogEndpoint({required this.method, required this.path});

  /// HTTP method, e.g. `GET`, `POST`.
  final String method;

  /// Absolute path, e.g. `/user/me`.
  final String path;

  /// Renders the endpoint as its CR content member.
  Map<String, Object?> toJson() => <String, Object?>{
    'method': method,
    'path': path,
  };
}

/// One per-endpoint catalog entry (C0 §14 `problems[]` shape).
///
/// The `type` URI is built in exactly ONE place; callers must pass a URI minted
/// by [problemTypeUri] (typically via [ProblemRegistry.typeUriFor] or
/// [ProblemCatalog.addType]) so no second template exists.
final class CatalogEntry {
  /// Creates a catalog entry.
  const CatalogEntry({
    required this.id,
    required this.typeUri,
    required this.title,
    required this.status,
    required this.recoverable,
    this.dataSchema = const <String, Object?>{},
    this.endpoints = const <CatalogEndpoint>[],
  });

  /// Stable problem id.
  final String id;

  /// RFC 9457 `type` URI (built by [problemTypeUri]).
  final String typeUri;

  /// Short human-readable title.
  final String title;

  /// HTTP status code.
  final int status;

  /// Recoverable-vs-fatal flag consumed by the frontend classifier.
  final bool recoverable;

  /// JSON Schema of the `data` extension payload.
  final Map<String, Object?> dataSchema;

  /// Endpoints that can return this problem.
  final List<CatalogEndpoint> endpoints;

  /// Renders the entry as its `Problem` CR content member (C0 §14).
  Map<String, Object?> toCrdContent() => <String, Object?>{
    'id': id,
    'type': typeUri,
    'title': title,
    'status': status,
    'recoverable': recoverable,
    'data': dataSchema,
    'endpoints': endpoints
        .map((CatalogEndpoint endpoint) => endpoint.toJson())
        .toList(growable: false),
  };
}

/// A per-service×landscape catalog of [CatalogEntry]s.
///
/// Builds entries from a [ProblemRegistry] (so the type URI is always the
/// single-source one) and emits the full `Problem` CR content payload.
final class ProblemCatalog {
  /// Creates an empty catalog bound to [portal].
  ProblemCatalog({required this.portal, List<CatalogEntry>? entries})
    : _entries = <String, CatalogEntry>{} {
    if (entries != null) {
      for (final CatalogEntry entry in entries) {
        add(entry);
      }
    }
  }

  /// Portal used when building type URIs for entries added via [addType].
  final ErrorPortal portal;

  final Map<String, CatalogEntry> _entries;

  /// Adds [entry]; replaces any existing entry with the same id.
  void add(CatalogEntry entry) => _entries[entry.id] = entry;

  /// Builds and adds an entry from a registry [type], attaching [endpoints].
  ///
  /// The type URI is minted by the single-source builder via the catalog's
  /// portal, so this is the canonical way to declare a cataloged problem.
  void addType(
    ProblemType type, {
    List<CatalogEndpoint> endpoints = const <CatalogEndpoint>[],
  }) {
    add(
      CatalogEntry(
        id: type.id,
        typeUri: problemTypeUri(
          portal: portal,
          version: type.version,
          id: type.id,
        ),
        title: type.title,
        status: type.status ?? 500,
        recoverable: type.recoverable,
        dataSchema: type.dataSchema,
        endpoints: endpoints,
      ),
    );
  }

  /// Adds the generic baseline set (see [GenericProblems]).
  void addGenerics() {
    for (final ProblemType type in GenericProblems.all) {
      addType(type);
    }
  }

  /// Looks up an entry by id, or `null` when absent.
  CatalogEntry? lookup(String id) => _entries[id];

  /// The declared entries in insertion order.
  Iterable<CatalogEntry> get entries => _entries.values;

  /// Emits the full `Problem` CR content payload (C0 §14): the `problems[]`
  /// list rendered per-row by the service's primordial chart.
  List<Map<String, Object?>> toCrdContent() => _entries.values
      .map((CatalogEntry entry) => entry.toCrdContent())
      .toList(growable: false);
}
