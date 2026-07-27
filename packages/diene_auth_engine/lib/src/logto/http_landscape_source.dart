import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/auth_engine_config.dart';
import '../home/landscape_selector.dart';

/// HTTP implementation of [LandscapeSelectorSource] (Doc B).
///
/// Enforces the baked endpoint-suffix allowlist on the doc URL at use time
/// (C0 §10) BEFORE fetching — a doc served off an unlisted host is untrusted.
final class HttpLandscapeSelectorSource implements LandscapeSelectorSource {
  HttpLandscapeSelectorSource({
    required this._docUrl,
    required this._config,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final Uri _docUrl;
  final AuthEngineConfig _config;
  final http.Client _client;

  @override
  Future<LandscapeSelectorDoc> fetch() async {
    if (!_config.allowsUrl(_docUrl)) {
      throw FormatException(
        'Doc B host is not endpoint-suffix-allowlisted',
        _docUrl.toString(),
      );
    }
    final http.Response response = await _client.get(_docUrl);
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Doc B fetch returned ${response.statusCode}',
        _docUrl,
      );
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Doc B must be a JSON object');
    }
    return LandscapeSelectorDoc.fromJson(
      decoded.map(
        (Object? key, Object? value) => MapEntry(key.toString(), value),
      ),
    );
  }
}

/// Derives a landscape's ping URL from its name — the convention, never
/// doc-carried (C0 §10).
typedef PingUrlBuilder = Uri Function(LandscapeEntry entry);

/// HTTP implementation of [RegionPinger]. Returns round-trip latency, or `null`
/// on any non-2xx / timeout / transport error.
final class HttpRegionPinger implements RegionPinger {
  HttpRegionPinger({
    required this._pingUrlOf,
    http.Client? client,
    this._timeout = const Duration(seconds: 3),
    Stopwatch Function()? stopwatch,
  }) : _client = client ?? http.Client(),
       _stopwatch = stopwatch ?? Stopwatch.new;

  final PingUrlBuilder _pingUrlOf;
  final http.Client _client;
  final Duration _timeout;
  final Stopwatch Function() _stopwatch;

  @override
  Future<Duration?> ping(LandscapeEntry entry) async {
    final Stopwatch watch = _stopwatch()..start();
    try {
      final http.Response response = await _client
          .get(_pingUrlOf(entry))
          .timeout(_timeout);
      watch.stop();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return watch.elapsed;
      }
      return null;
    } on Object {
      return null;
    }
  }
}
