/// Configuration + validator for the DORMANT rescue router (C0 §10;
/// goals/lib/dart-family.md, api-engine row).
///
/// The router is off the hot path: it trips ONLY on a hard connect-failure past
/// retry-once, then walks Doc C's ordered candidates with a jittered, budgeted
/// scan and pins the winner until the primary heals. It rescues ADDRESSES only,
/// within the same landscape — never cross-landscape.
///
/// Four settings are REQUIRED and all four are BAKED at build time:
///   1. a disk cache (last-known-good kept forever),
///   2. Doc A seeds spanning failure domains,
///   3. the endpoint-suffix allowlist,
///   4. the auth issuer — never doc-sourced.
///
/// Removing any one of them makes [validateRescueRouterConfig] red.
library;

import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import '../onboarding/picker.dart';

/// On-disk cache settings. Last-known-good is kept forever.
final class RescueDiskCacheConfig {
  const RescueDiskCacheConfig({
    required this.directory,
    required this.keepLastKnownGoodForever,
    required this.maxEntries,
  });

  final String directory;
  final bool keepLastKnownGoodForever;
  final int maxEntries;
}

/// The jittered, budgeted candidate scan.
final class RescueScanBudget {
  const RescueScanBudget({
    required this.totalBudget,
    required this.perCandidateTimeout,
    required this.maxJitter,
  });

  final Duration totalBudget;
  final Duration perCandidateTimeout;
  final Duration maxJitter;
}

/// The complete rescue-router configuration.
///
/// Every field is nullable so a MISSING setting is representable — that is what
/// the validator exists to reject. Wiring code should build this from baked
/// `--dart-define` values, never from a doc.
final class RescueRouterConfig {
  const RescueRouterConfig({
    required this.enabled,
    this.diskCache,
    this.seeds = const <Uri>[],
    this.allowlist,
    this.issuer,
    this.scanBudget,
  });

  /// Per-context enable flag: ON in Flutter, OFF in a server runtime.
  final bool enabled;

  final RescueDiskCacheConfig? diskCache;

  /// Baked Doc A seed addresses. They must span at least two distinct failure
  /// domains (registrable domains), which is the whole point of seeding.
  final List<Uri> seeds;

  /// The baked endpoint-suffix allowlist enforced on every doc-sourced URL.
  final EndpointSuffixAllowlist? allowlist;

  /// The baked OIDC issuer. Never doc-sourced (C0 §10).
  final Uri? issuer;

  final RescueScanBudget? scanBudget;
}

/// One validation failure.
final class RescueConfigViolation {
  const RescueConfigViolation({required this.setting, required this.detail});

  /// The required setting that is missing or invalid.
  final String setting;
  final String detail;

  @override
  String toString() => '$setting: $detail';
}

/// The four required settings, by name. Removing any one must go red.
const List<String> requiredRescueRouterSettings = <String>[
  'diskCache',
  'seeds',
  'allowlist',
  'issuer',
];

/// Validates a rescue-router configuration.
///
/// Returns the config on success; on failure a problem whose `data.violations`
/// names every missing/invalid setting.
Result<RescueRouterConfig> validateRescueRouterConfig(
  RescueRouterConfig config,
) {
  final List<RescueConfigViolation> violations = <RescueConfigViolation>[];

  final RescueDiskCacheConfig? cache = config.diskCache;
  if (cache == null) {
    violations.add(
      const RescueConfigViolation(
        setting: 'diskCache',
        detail: 'the router must cache Doc C to disk',
      ),
    );
  } else {
    if (cache.directory.isEmpty) {
      violations.add(
        const RescueConfigViolation(
          setting: 'diskCache',
          detail: 'directory must not be empty',
        ),
      );
    }
    if (!cache.keepLastKnownGoodForever) {
      violations.add(
        const RescueConfigViolation(
          setting: 'diskCache',
          detail: 'last-known-good must be kept forever',
        ),
      );
    }
    if (cache.maxEntries <= 0) {
      violations.add(
        const RescueConfigViolation(
          setting: 'diskCache',
          detail: 'maxEntries must be positive',
        ),
      );
    }
  }

  if (config.seeds.isEmpty) {
    violations.add(
      const RescueConfigViolation(
        setting: 'seeds',
        detail: 'at least one baked Doc A seed is required',
      ),
    );
  } else {
    final Set<String> domains = <String>{};
    for (final Uri seed in config.seeds) {
      if (seed.scheme != 'https' || authorityName(seed).isEmpty) {
        violations.add(
          RescueConfigViolation(
            setting: 'seeds',
            detail: 'seed $seed must be an absolute https URL',
          ),
        );
        continue;
      }
      domains.add(failureDomainOf(authorityName(seed), config.allowlist));
    }
    if (domains.length < 2) {
      violations.add(
        const RescueConfigViolation(
          setting: 'seeds',
          detail: 'seeds must span at least two failure domains',
        ),
      );
    }
  }

  final EndpointSuffixAllowlist? allowlist = config.allowlist;
  if (allowlist == null || allowlist.suffixes.isEmpty) {
    violations.add(
      const RescueConfigViolation(
        setting: 'allowlist',
        detail: 'the baked endpoint-suffix allowlist is required',
      ),
    );
  } else {
    for (final Uri seed in config.seeds) {
      final String authority = authorityName(seed);
      if (authority.isNotEmpty && !allowlist.allowsAuthority(authority)) {
        violations.add(
          RescueConfigViolation(
            setting: 'allowlist',
            detail: 'seed authority $authority is outside the allowlist',
          ),
        );
      }
    }
  }

  final Uri? issuer = config.issuer;
  if (issuer == null) {
    violations.add(
      const RescueConfigViolation(
        setting: 'issuer',
        detail: 'the auth issuer must be baked, never doc-sourced',
      ),
    );
  } else if (issuer.scheme != 'https' || authorityName(issuer).isEmpty) {
    violations.add(
      RescueConfigViolation(
        setting: 'issuer',
        detail: 'issuer $issuer must be an absolute https URL',
      ),
    );
  }

  final RescueScanBudget? budget = config.scanBudget;
  if (budget != null) {
    if (budget.totalBudget <= Duration.zero) {
      violations.add(
        const RescueConfigViolation(
          setting: 'scanBudget',
          detail: 'totalBudget must be positive',
        ),
      );
    }
    if (budget.perCandidateTimeout > budget.totalBudget) {
      violations.add(
        const RescueConfigViolation(
          setting: 'scanBudget',
          detail: 'perCandidateTimeout must not exceed totalBudget',
        ),
      );
    }
    if (budget.maxJitter < Duration.zero) {
      violations.add(
        const RescueConfigViolation(
          setting: 'scanBudget',
          detail: 'maxJitter must not be negative',
        ),
      );
    }
  }

  if (violations.isEmpty) {
    return Ok<RescueRouterConfig>(config);
  }
  return Err<RescueRouterConfig>(
    Problem(
      type: 'urn:diene:problem:rescue-router-config',
      title: 'Rescue router configuration is incomplete',
      status: 500,
      detail: violations.join('; '),
      data: <String, Object?>{
        'violations': violations
            .map((RescueConfigViolation v) => v.setting)
            .toList(growable: false),
      },
    ),
  );
}

/// Why the router was (or was not) consulted.
enum RescueTrip { hardConnectFailure, notTripped }

/// The dormant trip policy: hard connect-failure ONLY.
///
/// A soft/retryable error must never consult the router — that is the
/// dormancy contract (C0 §10).
RescueTrip classifyFailure({
  required bool isHardConnectFailure,
  required bool retryOnceExhausted,
  required bool enabled,
}) => enabled && isHardConnectFailure && retryOnceExhausted
    ? RescueTrip.hardConnectFailure
    : RescueTrip.notTripped;

/// The failure domain a seed authority belongs to.
///
/// C0 §10 seeds deliberately span failure domains — R2 behind a CF custom
/// domain, CloudFront behind the rescue domain, CloudFront's own name. Those
/// live under ONE registrable domain, so the registrable domain is the wrong
/// unit; the allowlist SUFFIX a seed matches is the real boundary. A seed
/// matching no suffix falls back to its registrable domain (it is a violation
/// on the allowlist rule anyway).
String failureDomainOf(String authority, EndpointSuffixAllowlist? allowlist) {
  final String normalized = authority.toLowerCase();
  final List<String> suffixes = allowlist?.suffixes ?? const <String>[];
  String? longest;
  for (final String suffix in suffixes) {
    final String s = suffix.toLowerCase();
    final bool matches =
        normalized == s.replaceFirst(RegExp(r'^\.'), '') ||
        normalized.endsWith(s);
    if (matches && (longest == null || s.length > longest.length)) {
      longest = s;
    }
  }
  if (longest != null) {
    return longest;
  }
  final List<String> labels = normalized.split('.');
  return labels.length <= 2
      ? normalized
      : labels.sublist(labels.length - 2).join('.');
}
