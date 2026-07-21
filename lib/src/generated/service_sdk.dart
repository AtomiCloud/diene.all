// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';

import 'clients/users_client.dart';

/// Diene Sample Service `v1.0.0`.
///
/// Minimal reviewed OA3 input for the diene_api_engine SDK-wrapper boundary. The generated retrofit client is wrapped into Result/Problem by OA3Adapter.
class ServiceSdk {
  ServiceSdk(
    Dio dio, {
    String? baseUrl,
  })  : _dio = dio,
        _baseUrl = baseUrl;

  final Dio _dio;
  final String? _baseUrl;

  static String get version => '1.0.0';

  UsersClient? _users;

  UsersClient get users => _users ??= UsersClient(_dio, baseUrl: _baseUrl);
}
