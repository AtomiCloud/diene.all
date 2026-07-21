import 'dart:convert';

import 'package:meta/meta.dart';

/// Doc A — the fleet doc. Just `catalogHosts[]` + a monotonic `version` that
/// doubles as the HTTP cache tag. Constantly refreshed; the "catalogs
/// advertise catalogs" carrier whose hosts span failure domains.
@immutable
class DocA {
  const DocA({required this.version, required this.catalogHosts});

  factory DocA.fromJson(Map<String, Object?> json) => DocA(
    version: (json['version'] as num).toInt(),
    catalogHosts:
        ((json['catalogHosts'] as List<Object?>?) ?? const <Object?>[])
            .map((Object? h) => h.toString())
            .toList(growable: false),
  );

  final int version;
  final List<String> catalogHosts;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'catalogHosts': catalogHosts,
  };
}

/// Doc C — the platform catalog (per platform × env). Full address book with
/// an ORDERED candidate list per `landscape.platform.service.module` (primary
/// root first, rescue after) so clients fail over without a mid-outage
/// republish. Dormant: fetched only when the router trips, then cached to
/// disk. Carries its own monotonic `version`.
@immutable
class DocC {
  const DocC({required this.version, required this.candidates});

  factory DocC.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> raw =
        (json['candidates'] as Map<Object?, Object?>? ??
                const <Object?, Object?>{})
            .map((Object? k, Object? v) => MapEntry(k.toString(), v));
    final Map<String, List<String>> parsed = <String, List<String>>{};
    for (final MapEntry<String, Object?> entry in raw.entries) {
      final Object? value = entry.value;
      if (value is List) {
        parsed[entry.key] = value
            .map((Object? u) => u.toString())
            .toList(growable: false);
      }
    }
    return DocC(version: (json['version'] as num).toInt(), candidates: parsed);
  }

  final int version;

  /// key = `landscape.platform.service.module` → ordered base-URL strings.
  final Map<String, List<String>> candidates;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'candidates': candidates,
  };

  String encode() => jsonEncode(toJson());

  static DocC? tryDecode(String body) {
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is Map<String, Object?>) {
        return DocC.fromJson(decoded);
      }
    } on Object {
      return null;
    }
    return null;
  }
}
