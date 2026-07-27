import 'dart:convert';

import 'package:diene_result/diene_result.dart';
import 'package:http/http.dart' as http;

import '../deferred/redeem_client.dart';

/// HTTP implementation of [AppHandoffApi] against `POST {mount}/redeem`.
///
/// Every non-success outcome — bad status, malformed body, transport error —
/// collapses to the single no-oracle [appHandoffExpired] problem (C0 §7).
final class HttpAppHandoffApi implements AppHandoffApi {
  HttpAppHandoffApi({
    required Uri base,
    required String redeemPath,
    http.Client? client,
  }) : _redeemUri = base.replace(path: _join(base.path, redeemPath)),
       _client = client ?? http.Client();

  final Uri _redeemUri;
  final http.Client _client;

  @override
  Future<Result<RedeemResult>> redeem({
    required String nonce,
    required DeviceInfo device,
  }) async {
    try {
      final http.Response response = await _client.post(
        _redeemUri,
        headers: const <String, String>{
          'content-type': 'application/json',
          'accept': 'application/json',
        },
        body: jsonEncode(<String, Object?>{
          'nonce': nonce,
          'device': device.toJson(),
        }),
      );
      if (response.statusCode != 200) {
        return Err<RedeemResult>(appHandoffExpired());
      }
      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return Err<RedeemResult>(appHandoffExpired());
      }
      final Object? token = decoded['token'];
      final Object? email = decoded['email'];
      if (token is! String || token.isEmpty || email is! String) {
        return Err<RedeemResult>(appHandoffExpired());
      }
      final Object? expiresIn = decoded['expiresIn'];
      return Ok<RedeemResult>(
        RedeemResult(
          token: token,
          email: email,
          expiresIn: expiresIn is int ? expiresIn : 120,
        ),
      );
    } on Object {
      return Err<RedeemResult>(appHandoffExpired());
    }
  }

  static String _join(String base, String path) {
    final String left = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    final String right = path.startsWith('/') ? path : '/$path';
    return '$left$right';
  }
}
