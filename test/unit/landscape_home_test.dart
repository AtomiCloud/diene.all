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
    test('rejects a doc that leaks addresses or an issuer', () {
      // Assert — names + metadata ONLY.
      expect(
        () => LandscapeSelectorDoc.fromJson(<String, Object?>{
          'platform': 'lithium',
          'tier': 'prod',
          'landscapes': <Object?>[
            <String, Object?>{
              'name': 'a',
              'region': 'r',
              'issuer': 'https://evil',
            },
          ],
        }),
        throwsFormatException,
      );
    });
  });

  group('HomeClaimResolver', () {
    test('cached claim routes home without touching Doc B', () async {
      // Arrange
      final FakeLandscapeSelectorSource source = FakeLandscapeSelectorSource(
        doc: _doc(<String>['a']),
      );
      final HomeClaimResolver resolver = HomeClaimResolver(
        store: MemoryHomeClaimStore('pichu'),
        selector: LandscapeSelectorClient(
          source: source,
          pinger: FakeRegionPinger(const <String, Duration?>{}),
        ),
      );

      // Act
      final Result<HomeResolution> result = await resolver.resolve();

      // Assert
      final HomeResolution home = AuthExpect.ok(result);
      expect(home.landscape, 'pichu');
      expect(home.kind, HomeResolutionKind.cached);
      expect(source.fetchCount, 0);
    });

    test('absent claim runs the sign-up selector', () async {
      // Arrange
      final HomeClaimResolver resolver = HomeClaimResolver(
        store: MemoryHomeClaimStore(),
        selector: LandscapeSelectorClient(
          source: FakeLandscapeSelectorSource(doc: _doc(<String>['a'])),
          pinger: FakeRegionPinger(<String, Duration?>{
            'a': const Duration(milliseconds: 10),
          }),
        ),
      );

      // Act
      final HomeResolution home = AuthExpect.ok(await resolver.resolve());

      // Assert
      expect(home.landscape, 'a');
      expect(home.kind, HomeResolutionKind.selected);
    });

    test('commit mirrors the claim into the store', () async {
      // Arrange
      final MemoryHomeClaimStore store = MemoryHomeClaimStore();
      final HomeClaimResolver resolver = HomeClaimResolver(
        store: store,
        selector: LandscapeSelectorClient(
          source: FakeLandscapeSelectorSource(doc: _doc(<String>['a'])),
          pinger: FakeRegionPinger(const <String, Duration?>{}),
        ),
      );

      // Act
      await resolver.commit('raichu');

      // Assert
      expect(store.value, 'raichu');
    });
  });
}
