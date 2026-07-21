import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:diene_auth_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

LandscapeSelectorDoc _doc(List<String> names) => LandscapeSelectorDoc(
  platform: 'lithium',
  tier: 'prod',
  landscapes: <LandscapeEntry>[
    for (final String name in names)
      LandscapeEntry(name: name, region: '$name-region'),
  ],
);

void main() {
  group('LandscapeSelectorClient', () {
    test('picks the fastest healthy region', () async {
      // Arrange
      final LandscapeSelectorClient client = LandscapeSelectorClient(
        source: FakeLandscapeSelectorSource(doc: _doc(<String>['a', 'b', 'c'])),
        pinger: FakeRegionPinger(<String, Duration?>{
          'a': const Duration(milliseconds: 90),
          'b': const Duration(milliseconds: 30),
          'c': null, // unhealthy
        }),
      );

      // Act
      final Result<String> result = await client.selectHome();

      // Assert
      expect(AuthExpect.ok(result), 'b');
    });

    test('honours a healthy preference over the fastest', () async {
      // Arrange
      final LandscapeSelectorClient client = LandscapeSelectorClient(
        source: FakeLandscapeSelectorSource(doc: _doc(<String>['a', 'b'])),
        pinger: FakeRegionPinger(<String, Duration?>{
          'a': const Duration(milliseconds: 90),
          'b': const Duration(milliseconds: 30),
        }),
      );

      // Act
      final Result<String> result = await client.selectHome(preferred: 'a');

      // Assert
      expect(AuthExpect.ok(result), 'a');
    });

    test('fails when no region is healthy', () async {
      // Arrange
      final LandscapeSelectorClient client = LandscapeSelectorClient(
        source: FakeLandscapeSelectorSource(doc: _doc(<String>['a'])),
        pinger: FakeRegionPinger(<String, Duration?>{'a': null}),
      );

      // Act + Assert
      expect(await client.selectHome(), isA<Failure<String>>());
    });

    test('propagates a doc fetch failure', () async {
      // Arrange
      final LandscapeSelectorClient client = LandscapeSelectorClient(
        source: FakeLandscapeSelectorSource(error: StateError('offline')),
        pinger: FakeRegionPinger(const <String, Duration?>{}),
      );

      // Act + Assert
      expect(await client.selectHome(), isA<Failure<String>>());
    });
  });

  group('Doc B parser', () {
    Object docWith(Map<String, Object?> entry) => <String, Object?>{
      'platform': 'lithium',
      'tier': 'prod',
      'landscapes': <Object?>[
        <String, Object?>{'name': 'a', 'region': 'r', ...entry},
      ],
    };

    test('rejects a top-level issuer/address key', () {
      expect(
        () => LandscapeSelectorDoc.fromJson(
          docWith(<String, Object?>{'issuer': 'https://evil'})
              as Map<String, Object?>,
        ),
        throwsFormatException,
      );
    });

    test('rejects a prohibited key nested inside metadata', () {
      expect(
        () => LandscapeSelectorDoc.fromJson(
          docWith(<String, Object?>{
                'metadata': <String, Object?>{'issuer': 'https://sneaky'},
              })
              as Map<String, Object?>,
        ),
        throwsFormatException,
      );
    });

    test('rejects a deeply nested address key', () {
      expect(
        () => LandscapeSelectorDoc.fromJson(
          docWith(<String, Object?>{
                'metadata': <String, Object?>{
                  'ops': <String, Object?>{
                    'nested': <String, Object?>{'host': 'x.internal'},
                  },
                },
              })
              as Map<String, Object?>,
        ),
        throwsFormatException,
      );
    });

    test('rejects a URL-shaped value hidden under a benign key', () {
      expect(
        () => LandscapeSelectorDoc.fromJson(
          docWith(<String, Object?>{
                'metadata': <String, Object?>{
                  'note': 'see https://leak.example/doc',
                },
              })
              as Map<String, Object?>,
        ),
        throwsFormatException,
      );
    });

    test('rejects a protocol-relative value in a metadata list', () {
      expect(
        () => LandscapeSelectorDoc.fromJson(
          docWith(<String, Object?>{
                'metadata': <String, Object?>{
                  'tags': <Object?>['ok', '//evil.example'],
                },
              })
              as Map<String, Object?>,
        ),
        throwsFormatException,
      );
    });

    test('accepts safe names + benign metadata', () {
      final LandscapeSelectorDoc doc = LandscapeSelectorDoc.fromJson(
        docWith(<String, Object?>{
              'metadata': <String, Object?>{
                'display': 'Region A',
                'healthy': true,
              },
            })
            as Map<String, Object?>,
      );
      expect(doc.landscapes.single.metadata['display'], 'Region A');
    });
  });

  group('jwtHomeClaimReader', () {
    test('decodes home_landscape from the ID token', () async {
      final HomeClaimReader reader = jwtHomeClaimReader(
        () async => AuthFixtures.jwt(<String, Object?>{
          Claims.homeLandscape: 'pikachu',
        }),
      );
      expect(await reader(), 'pikachu');
    });

    test('returns null for a missing token', () async {
      final HomeClaimReader reader = jwtHomeClaimReader(() async => null);
      expect(await reader(), isNull);
    });
  });

  group('HomeClaimResolver', () {
    HomeClaimResolver resolver({
      required HomeClaimReader claimReader,
      HomeClaimReader? forcedClaimReader,
      FakeLandscapeSelectorSource? source,
      HomeClaimStore? store,
      Map<String, Duration?> latencies = const <String, Duration?>{
        'a': Duration(milliseconds: 10),
      },
    }) => HomeClaimResolver(
      claimReader: claimReader,
      forcedClaimReader: forcedClaimReader,
      store: store,
      selector: LandscapeSelectorClient(
        source: source ?? FakeLandscapeSelectorSource(doc: _doc(<String>['a'])),
        pinger: FakeRegionPinger(latencies),
      ),
    );

    test(
      'confirmedHome reads the FORCED claim reader (post-OnboardSync)',
      () async {
        // Present forced claim → confirmed.
        expect(
          AuthExpect.ok(
            await resolver(
              claimReader: () async => null,
              forcedClaimReader: () async => 'raichu',
            ).confirmedHome(),
          ),
          'raichu',
        );
        // Forced claim absent → null (fail-closed).
        expect(
          AuthExpect.ok(
            await resolver(
              claimReader: () async => null,
              forcedClaimReader: () async => null,
            ).confirmedHome(),
          ),
          isNull,
        );
        // No forced reader wired → null (fail-closed).
        expect(
          AuthExpect.ok(
            await resolver(claimReader: () async => null).confirmedHome(),
          ),
          isNull,
        );
      },
    );

    test(
      'authoritative JWT claim routes home without touching Doc B',
      () async {
        // Arrange
        final FakeLandscapeSelectorSource source = FakeLandscapeSelectorSource(
          doc: _doc(<String>['a']),
        );
        final HomeClaimResolver r = resolver(
          claimReader: () async => 'pichu',
          source: source,
        );

        // Act
        final HomeResolution home = AuthExpect.ok(await r.resolve());

        // Assert
        expect(home.landscape, 'pichu');
        expect(home.kind, HomeResolutionKind.fromClaim);
        expect(source.fetchCount, 0);
      },
    );

    test('JWT claim overrides a disagreeing local cache', () async {
      // Arrange — cache says raichu, but the authoritative JWT says pichu.
      final MemoryHomeClaimStore store = MemoryHomeClaimStore('raichu');
      final HomeClaimResolver r = resolver(
        claimReader: () async => 'pichu',
        store: store,
      );

      // Act
      final HomeResolution home = AuthExpect.ok(await r.resolve());

      // Assert — JWT wins and the mirror is corrected.
      expect(home.landscape, 'pichu');
      expect(home.kind, HomeResolutionKind.fromClaim);
      expect(store.value, 'pichu');
    });

    test(
      'absent JWT claim runs Doc B even when the cache is populated',
      () async {
        // Arrange — a stale cache must NOT choose the home; the claim is absent.
        final FakeLandscapeSelectorSource source = FakeLandscapeSelectorSource(
          doc: _doc(<String>['a']),
        );
        final HomeClaimResolver r = resolver(
          claimReader: () async => null,
          source: source,
          store: MemoryHomeClaimStore('raichu'),
        );

        // Act
        final HomeResolution home = AuthExpect.ok(await r.resolve());

        // Assert — Doc B decided, not the cache.
        expect(home.landscape, 'a');
        expect(home.kind, HomeResolutionKind.selected);
        expect(source.fetchCount, 1);
      },
    );

    test('authoritativeHome reports absent vs present without Doc B', () async {
      // Assert
      expect(
        AuthExpect.ok(
          await resolver(claimReader: () async => null).authoritativeHome(),
        ),
        isNull,
      );
      expect(
        AuthExpect.ok(
          await resolver(claimReader: () async => 'lapras').authoritativeHome(),
        ),
        'lapras',
      );
    });

    test('commit mirrors the claim into the store', () async {
      // Arrange
      final MemoryHomeClaimStore store = MemoryHomeClaimStore();
      final HomeClaimResolver r = resolver(
        claimReader: () async => null,
        store: store,
      );

      // Act
      await r.commit('raichu');

      // Assert
      expect(store.value, 'raichu');
    });
  });
}
