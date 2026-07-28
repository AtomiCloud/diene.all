import 'package:diene_flutter_base/auth/rescue_router_config.dart';
import 'package:diene_flutter_base/onboarding/picker.dart';
import 'package:diene_result/diene_result.dart';
import 'package:flutter_test/flutter_test.dart';

const RescueDiskCacheConfig _diskCache = RescueDiskCacheConfig(
  directory: '/var/app/rescue',
  keepLastKnownGoodForever: true,
  maxEntries: 32,
);

/// Seeds deliberately span two failure domains, as C0 §10 requires.
final List<Uri> _seeds = <Uri>[
  Uri.parse('https://fleet.rescue.atomi.cloud/doc-a.json'),
  Uri.parse('https://fleet.edge.platform.raichu.cluster.atomi.cloud/doc-a.json'),
];

const EndpointSuffixAllowlist _allowlist = EndpointSuffixAllowlist(
  <String>['.cluster.atomi.cloud', '.rescue.atomi.cloud'],
);

final Uri _issuer = Uri.parse(
  'https://api.lithium.platform.mew.cluster.atomi.cloud',
);

const RescueScanBudget _budget = RescueScanBudget(
  totalBudget: Duration(seconds: 6),
  perCandidateTimeout: Duration(seconds: 2),
  maxJitter: Duration(milliseconds: 250),
);

/// A fully-wired configuration. Each test removes exactly ONE setting.
RescueRouterConfig _complete({
  RescueDiskCacheConfig? diskCache = _diskCache,
  List<Uri>? seeds,
  EndpointSuffixAllowlist? allowlist = _allowlist,
  Uri? issuer,
  RescueScanBudget? scanBudget = _budget,
  bool enabled = true,
}) => RescueRouterConfig(
  enabled: enabled,
  diskCache: diskCache,
  seeds: seeds ?? _seeds,
  allowlist: allowlist,
  issuer: issuer ?? _issuer,
  scanBudget: scanBudget,
);

List<String> _violations(Result<RescueRouterConfig> result) =>
    ((result as Err<RescueRouterConfig>).problem.data['violations']!
            as List<Object?>)
        .map((Object? v) => v.toString())
        .toList(growable: false);

void main() {
  test('the fully-wired configuration validates', () {
    final Result<RescueRouterConfig> result = validateRescueRouterConfig(
      _complete(),
    );

    expect(
      result.isOk,
      isTrue,
      reason: 'a validator that never passes is as useless as one that never '
          'fails',
    );
  });

  group('removing any one required setting goes red', () {
    test('no disk cache', () {
      final Result<RescueRouterConfig> result = validateRescueRouterConfig(
        _complete(diskCache: null),
      );

      expect(result, isA<Err<RescueRouterConfig>>());
      expect(_violations(result), contains('diskCache'));
    });

    test('no seeds', () {
      final Result<RescueRouterConfig> result = validateRescueRouterConfig(
        _complete(seeds: const <Uri>[]),
      );

      expect(result, isA<Err<RescueRouterConfig>>());
      expect(_violations(result), contains('seeds'));
    });

    test('no allowlist', () {
      final Result<RescueRouterConfig> result = validateRescueRouterConfig(
        _complete(allowlist: null),
      );

      expect(result, isA<Err<RescueRouterConfig>>());
      expect(_violations(result), contains('allowlist'));
    });

    test('no issuer', () {
      final Result<RescueRouterConfig> result = validateRescueRouterConfig(
        RescueRouterConfig(
          enabled: true,
          diskCache: _diskCache,
          seeds: _seeds,
          allowlist: _allowlist,
          scanBudget: _budget,
        ),
      );

      expect(result, isA<Err<RescueRouterConfig>>());
      expect(_violations(result), contains('issuer'));
    });

    test('every required setting is covered by this group', () {
      // Guards against a setting being added to the config without a
      // corresponding removal case here.
      expect(requiredRescueRouterSettings, <String>[
        'diskCache',
        'seeds',
        'allowlist',
        'issuer',
      ]);
    });
  });

  group('settings that are present but wrong', () {
    test('a disk cache that discards last-known-good is rejected', () {
      final Result<RescueRouterConfig> result = validateRescueRouterConfig(
        _complete(
          diskCache: const RescueDiskCacheConfig(
            directory: '/var/app/rescue',
            keepLastKnownGoodForever: false,
            maxEntries: 32,
          ),
        ),
      );

      expect(_violations(result), contains('diskCache'));
    });

    test('an empty cache directory is rejected', () {
      final Result<RescueRouterConfig> result = validateRescueRouterConfig(
        _complete(
          diskCache: const RescueDiskCacheConfig(
            directory: '',
            keepLastKnownGoodForever: true,
            maxEntries: 32,
          ),
        ),
      );

      expect(_violations(result), contains('diskCache'));
    });

    test('seeds inside one failure domain are rejected', () {
      final Result<RescueRouterConfig> result = validateRescueRouterConfig(
        _complete(
          seeds: <Uri>[
            Uri.parse('https://a.rescue.atomi.cloud/doc-a.json'),
            Uri.parse('https://b.rescue.atomi.cloud/doc-a.json'),
          ],
        ),
      );

      expect(
        _violations(result),
        contains('seeds'),
        reason: 'seeding two names in one domain defeats the point',
      );
    });

    test('a seed outside the allowlist is rejected', () {
      final Result<RescueRouterConfig> result = validateRescueRouterConfig(
        _complete(
          seeds: <Uri>[
            Uri.parse('https://fleet.rescue.atomi.cloud/doc-a.json'),
            Uri.parse('https://cdn.example.invalid/doc-a.json'),
          ],
        ),
      );

      expect(_violations(result), contains('allowlist'));
    });

    test('a non-https seed is rejected', () {
      final Result<RescueRouterConfig> result = validateRescueRouterConfig(
        _complete(
          seeds: <Uri>[
            Uri.parse('http://fleet.rescue.atomi.cloud/doc-a.json'),
            Uri.parse(
              'https://fleet.edge.platform.raichu.cluster.atomi.cloud/a.json',
            ),
          ],
        ),
      );

      expect(_violations(result), contains('seeds'));
    });

    test('a non-https issuer is rejected', () {
      final Result<RescueRouterConfig> result = validateRescueRouterConfig(
        _complete(issuer: Uri.parse('http://issuer.example.invalid')),
      );

      expect(_violations(result), contains('issuer'));
    });

    test('an empty allowlist is rejected', () {
      final Result<RescueRouterConfig> result = validateRescueRouterConfig(
        _complete(allowlist: const EndpointSuffixAllowlist(<String>[])),
      );

      expect(_violations(result), contains('allowlist'));
    });

    test('a scan budget shorter than one candidate is rejected', () {
      final Result<RescueRouterConfig> result = validateRescueRouterConfig(
        _complete(
          scanBudget: const RescueScanBudget(
            totalBudget: Duration(seconds: 1),
            perCandidateTimeout: Duration(seconds: 2),
            maxJitter: Duration(milliseconds: 250),
          ),
        ),
      );

      expect(_violations(result), contains('scanBudget'));
    });

    test('multiple missing settings are all reported at once', () {
      final Result<RescueRouterConfig> result = validateRescueRouterConfig(
        RescueRouterConfig(
          enabled: true,
          seeds: _seeds,
          allowlist: _allowlist,
        ),
      );

      expect(_violations(result), containsAll(<String>['diskCache', 'issuer']));
    });
  });

  group('dormancy: the router trips on hard connect-failure only', () {
    test('a hard connect-failure past retry-once trips it', () {
      expect(
        classifyFailure(
          isHardConnectFailure: true,
          retryOnceExhausted: true,
          enabled: true,
        ),
        RescueTrip.hardConnectFailure,
      );
    });

    test('a soft/retryable error never trips it', () {
      expect(
        classifyFailure(
          isHardConnectFailure: false,
          retryOnceExhausted: true,
          enabled: true,
        ),
        RescueTrip.notTripped,
        reason: 'the router is off the hot path',
      );
    });

    test('a hard failure before retry-once is exhausted does not trip', () {
      expect(
        classifyFailure(
          isHardConnectFailure: true,
          retryOnceExhausted: false,
          enabled: true,
        ),
        RescueTrip.notTripped,
      );
    });

    test('the per-context disable flag wins over everything', () {
      expect(
        classifyFailure(
          isHardConnectFailure: true,
          retryOnceExhausted: true,
          enabled: false,
        ),
        RescueTrip.notTripped,
        reason: 'a disabled context must never run the router',
      );
    });
  });
}
