import 'package:meta/meta.dart';

/// Full resource identity (C0 §8, S7):
/// `ResourceKey = (platform, landscape, service, resourceName)`.
///
/// Every component is an explicit lowercase DNS label; none is inferred.
/// `resourceName` occupies the M slot of the public LPSM coordinate, so the
/// Logto resource identifier / JWT `aud` is exactly
/// `https://<resourceName>.<service>.<platform>.<landscape>.cluster.atomi.cloud`
/// (no trailing slash). The identifier is an identity string; dereferenceability
/// is not required.
@immutable
final class ResourceKey {
  ResourceKey({
    required this.platform,
    required this.landscape,
    required this.service,
    required this.resourceName,
    this.domain = 'cluster.atomi.cloud',
  }) {
    for (final MapEntry<String, String> label in <String, String>{
      'platform': platform,
      'landscape': landscape,
      'service': service,
      'resourceName': resourceName,
    }.entries) {
      if (!_dnsLabel.hasMatch(label.value)) {
        throw FormatException(
          'ResourceKey.${label.key} must be a lowercase DNS label',
          label.value,
        );
      }
    }
  }

  static final RegExp _dnsLabel = RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?$');

  final String platform;
  final String landscape;
  final String service;
  final String resourceName;
  final String domain;

  /// Canonical client-map key: `platform/landscape/service/resourceName`.
  String get mapKey => '$platform/$landscape/$service/$resourceName';

  /// The Logto resource indicator / JWT `aud` (no trailing slash).
  Uri get audience =>
      Uri.parse('https://$resourceName.$service.$platform.$landscape.$domain');

  @override
  bool operator ==(Object other) =>
      other is ResourceKey && other.mapKey == mapKey && other.domain == domain;

  @override
  int get hashCode => Object.hash(mapKey, domain);

  @override
  String toString() => 'ResourceKey($mapKey)';
}
