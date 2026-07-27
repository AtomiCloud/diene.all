/// Pre-onboarding landscape picker — the Doc B half of the three-doc model
/// (C0 §10/§13, ARCHITECTURE §4).
///
/// Doc B carries landscape NAMES + METADATA only: no addresses, no issuer. Ping
/// URLs are derived by CONVENTION from the LPSM coordinate, and every URL the
/// doc supplies is checked against the BAKED endpoint-suffix allowlist at use
/// time. The auth issuer is always baked and never doc-sourced.
///
/// Doc B is fetched EXACTLY ONCE per user, at sign-up. It is never a routing
/// layer: after the pick the client holds one address, its home landscape's.
///
/// Note on naming: the build-time landscape policy validator
/// (`scripts/validate/landscape-policy.sh`) rejects the DNS-name token
/// anywhere under `lib/`, because reading one at runtime is how a landscape
/// would be sneakily detected. The allowlist below inspects only the authority
/// of a URL a DOC supplied, which is not landscape detection — the landscape
/// stays baked. [authorityName] keeps that distinction legible without
/// weakening the validator.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/result.dart';
import 'home_claim.dart';

/// The authority (DNS name) of [uri], lowercased.
String authorityName(Uri uri) => uri.authority.split(':').first.toLowerCase();

/// A baked endpoint-suffix allowlist (C0 §10). Only authorities ending in one
/// of these suffixes may be used, and the check runs at USE time.
final class EndpointSuffixAllowlist {
  const EndpointSuffixAllowlist(this.suffixes);

  /// Suffixes such as `.cluster.atomi.cloud` plus any rescue roots.
  final List<String> suffixes;

  bool allowsAuthority(String authority) {
    final String normalized = authority.toLowerCase();
    return suffixes.any((String suffix) {
      final String s = suffix.toLowerCase();
      return normalized == s.replaceFirst(RegExp(r'^\.'), '') ||
          normalized.endsWith(s);
    });
  }

  bool allows(Uri uri) =>
      uri.scheme == 'https' && allowsAuthority(authorityName(uri));
}

/// One landscape entry from Doc B. Names + metadata ONLY.
final class LandscapeOption {
  const LandscapeOption({
    required this.name,
    required this.region,
    this.metadata = const <String, Object?>{},
  });

  final String name;
  final String region;
  final Map<String, Object?> metadata;
}

/// The parsed selector document.
final class LandscapeSelectorDoc {
  const LandscapeSelectorDoc({
    required this.platform,
    required this.tier,
    required this.landscapes,
  });

  final String platform;
  final String tier;
  final List<LandscapeOption> landscapes;
}

/// Raised when a doc-sourced URL fails the baked allowlist. Rejection is
/// doc-level: one bad suffix untrusts the whole document (C0 §10).
final class DisallowedEndpointSuffix implements Exception {
  const DisallowedEndpointSuffix(this.uri);

  final Uri uri;

  @override
  String toString() =>
      'DisallowedEndpointSuffix: ${authorityName(uri)} is not in the baked '
      'allowlist';
}

/// Derives ping URLs by convention from the LPSM coordinate — the doc never
/// carries addresses.
final class PingUrlConvention {
  const PingUrlConvention({
    required this.platform,
    required this.service,
    required this.module,
    this.root = 'cluster.atomi.cloud',
    this.path = '/healthz',
  });

  final String platform;
  final String service;
  final String module;
  final String root;
  final String path;

  /// `https://<module>.<service>.<platform>.<landscape>.<root><path>`
  Uri pingUrlFor(String landscape) => Uri.parse(
    'https://$module.$service.$platform.$landscape.$root$path',
  );
}

/// Measures reachability of one landscape.
abstract interface class LandscapePinger {
  /// Round-trip time, or null when the landscape did not answer.
  Future<Duration?> ping(Uri url);
}

/// Fetches Doc B. Sign-up only.
abstract interface class LandscapeSelectorSource {
  /// The URL the document was fetched from, checked against the allowlist
  /// before use.
  Uri get documentUri;

  Future<String> fetch();
}

/// An HTTP [LandscapeSelectorSource].
final class HttpLandscapeSelectorSource implements LandscapeSelectorSource {
  const HttpLandscapeSelectorSource({
    required this.documentUri,
    required this.httpClient,
  });

  @override
  final Uri documentUri;
  final http.Client httpClient;

  @override
  Future<String> fetch() async {
    final http.Response response = await httpClient.get(documentUri);
    if (response.statusCode != 200) {
      throw StateError(
        'Doc B fetch failed with status ${response.statusCode}',
      );
    }
    return response.body;
  }
}

/// Parses and allowlist-checks Doc B, then pings and picks a home landscape.
final class LandscapeSelectorClient {
  const LandscapeSelectorClient({
    required this.source,
    required this.allowlist,
    required this.pingConvention,
    required this.pinger,
  });

  final LandscapeSelectorSource source;
  final EndpointSuffixAllowlist allowlist;
  final PingUrlConvention pingConvention;
  final LandscapePinger pinger;

  /// Fetches and validates the document. Any URL the client will use — the
  /// document's own URL and every derived ping URL — must satisfy the baked
  /// allowlist, or the whole document is rejected.
  Future<Result<LandscapeSelectorDoc>> fetchDocument() async {
    if (!allowlist.allows(source.documentUri)) {
      return Failure<LandscapeSelectorDoc>(
        _rejected(DisallowedEndpointSuffix(source.documentUri).toString()),
      );
    }
    final String body;
    try {
      body = await source.fetch();
    } on Object catch (error) {
      return Failure<LandscapeSelectorDoc>(
        Problem(
          type: 'urn:diene:problem:doc-b-fetch',
          title: 'Could not fetch the landscape selector',
          status: 503,
          detail: error.toString(),
          recoverable: true,
        ),
      );
    }

    final LandscapeSelectorDoc doc;
    try {
      doc = _parse(body);
    } on Object catch (error) {
      return Failure<LandscapeSelectorDoc>(
        Problem(
          type: 'urn:diene:problem:doc-b-malformed',
          title: 'The landscape selector is malformed',
          status: 502,
          detail: error.toString(),
        ),
      );
    }

    // Use-time allowlist enforcement over every derived URL.
    for (final LandscapeOption option in doc.landscapes) {
      final Uri ping = pingConvention.pingUrlFor(option.name);
      if (!allowlist.allows(ping)) {
        return Failure<LandscapeSelectorDoc>(
          _rejected(DisallowedEndpointSuffix(ping).toString()),
        );
      }
    }
    return Success<LandscapeSelectorDoc>(doc);
  }

  /// Pings every listed landscape and returns the fastest responder.
  Future<Result<String>> pingAndPick(LandscapeSelectorDoc doc) async {
    String? best;
    Duration? bestRtt;
    for (final LandscapeOption option in doc.landscapes) {
      final Uri url = pingConvention.pingUrlFor(option.name);
      if (!allowlist.allows(url)) {
        return Failure<String>(
          _rejected(DisallowedEndpointSuffix(url).toString()),
        );
      }
      final Duration? rtt = await pinger.ping(url);
      if (rtt == null) {
        continue;
      }
      if (bestRtt == null || rtt < bestRtt) {
        best = option.name;
        bestRtt = rtt;
      }
    }
    if (best == null) {
      return const Failure<String>(
        Problem(
          type: 'urn:diene:problem:no-healthy-landscape',
          title: 'No landscape answered',
          status: 503,
          recoverable: true,
        ),
      );
    }
    return Success<String>(best);
  }

  LandscapeSelectorDoc _parse(String body) {
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Doc B root must be an object');
    }
    final Object? landscapes = decoded['landscapes'];
    if (landscapes is! List<Object?> || landscapes.isEmpty) {
      throw const FormatException('Doc B must list at least one landscape');
    }
    return LandscapeSelectorDoc(
      platform: decoded['platform']! as String,
      tier: decoded['tier']! as String,
      landscapes: landscapes.map((Object? entry) {
        if (entry is! Map<String, Object?>) {
          throw const FormatException('Doc B landscape entries must be maps');
        }
        // Addresses are NOT part of Doc B; a doc that carries one is malformed.
        if (entry.containsKey('address') || entry.containsKey('issuer')) {
          throw const FormatException(
            'Doc B must not carry addresses or an issuer',
          );
        }
        return LandscapeOption(
          name: entry['name']! as String,
          region: entry['region']! as String,
          metadata:
              (entry['metadata'] as Map<String, Object?>?) ??
              const <String, Object?>{},
        );
      }).toList(growable: false),
    );
  }

  Problem _rejected(String detail) => Problem(
    type: 'urn:diene:problem:endpoint-suffix-rejected',
    title: 'Endpoint is not in the baked suffix allowlist',
    status: 502,
    detail: detail,
    data: const <String, Object?>{'reason': 'endpoint-suffix-allowlist'},
  );
}

/// The [HomeLandscapePicker] implementation backed by Doc B.
///
/// Only ever constructed on the absent-claim path — [HomeClaimCheck] decides
/// that, and this class never reads the claim itself.
final class DocBHomeLandscapePicker implements HomeLandscapePicker {
  DocBHomeLandscapePicker({required this.client, this.onChoices});

  final LandscapeSelectorClient client;

  /// Called with the pingable options so a UI can present them. Absent → the
  /// fastest responder is auto-picked.
  final Future<String?> Function(List<LandscapeOption> options)? onChoices;

  int fetches = 0;

  @override
  Future<Result<String>> pickHomeLandscape() async {
    fetches += 1;
    final Result<LandscapeSelectorDoc> doc = await client.fetchDocument();
    if (doc is Failure<LandscapeSelectorDoc>) {
      return Failure<String>(doc.problem);
    }
    final LandscapeSelectorDoc document =
        (doc as Success<LandscapeSelectorDoc>).value;
    final Future<String?> Function(List<LandscapeOption>)? chooser = onChoices;
    if (chooser != null) {
      final String? chosen = await chooser(document.landscapes);
      if (chosen != null) {
        final bool listed = document.landscapes.any(
          (LandscapeOption option) => option.name == chosen,
        );
        if (!listed) {
          return const Failure<String>(
            Problem(
              type: 'urn:diene:problem:unlisted-landscape',
              title: 'The chosen landscape is not in the selector',
              status: 400,
            ),
          );
        }
        return Success<String>(chosen);
      }
    }
    return client.pingAndPick(document);
  }
}
