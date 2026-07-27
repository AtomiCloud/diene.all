import 'dart:convert';

import 'package:diene_flutter_base/core/result.dart';
import 'package:diene_flutter_base/onboarding/home_claim.dart';
import 'package:diene_flutter_base/onboarding/picker.dart';
import 'package:flutter_test/flutter_test.dart';

const EndpointSuffixAllowlist _allowlist = EndpointSuffixAllowlist(
  <String>['.cluster.atomi.cloud', '.rescue.atomi.cloud'],
);

const PingUrlConvention _convention = PingUrlConvention(
  platform: 'platform',
  service: 'service',
  module: 'api',
);

final class _StubSource implements LandscapeSelectorSource {
  _StubSource({required this.documentUri, required this.body});

  @override
  final Uri documentUri;
  final String body;
  int fetches = 0;

  @override
  Future<String> fetch() async {
    fetches += 1;
    return body;
  }
}

final class _StubPinger implements LandscapePinger {
  _StubPinger(this.rtts);

  /// Keyed by landscape name; a missing entry means no answer.
  final Map<String, Duration?> rtts;
  final List<Uri> pinged = <Uri>[];

  @override
  Future<Duration?> ping(Uri url) async {
    pinged.add(url);
    final String landscape = authorityName(url).split('.')[3];
    return rtts[landscape];
  }
}

String _docB({
  List<String> landscapes = const <String>['pichu', 'pikachu', 'raichu'],
  Map<String, Object?>? extraOnFirst,
}) => jsonEncode(<String, Object?>{
  'platform': 'platform',
  'tier': 'production',
  'landscapes': <Object?>[
    for (final String name in landscapes)
      <String, Object?>{
        'name': name,
        'region': 'region-$name',
        'metadata': <String, Object?>{'label': name},
        if (name == landscapes.first && extraOnFirst != null) ...extraOnFirst,
      },
  ],
});

LandscapeSelectorClient _client({
  required _StubSource source,
  required _StubPinger pinger,
  EndpointSuffixAllowlist allowlist = _allowlist,
  PingUrlConvention convention = _convention,
}) => LandscapeSelectorClient(
  source: source,
  allowlist: allowlist,
  pingConvention: convention,
  pinger: pinger,
);

_StubSource _source({String? body, String? uri}) => _StubSource(
  documentUri: Uri.parse(
    uri ?? 'https://docs.edge.platform.raichu.cluster.atomi.cloud/doc-b.json',
  ),
  body: body ?? _docB(),
);

void main() {
  group('endpoint-suffix allowlist', () {
    test('accepts a baked suffix over https', () {
      expect(
        _allowlist.allows(
          Uri.parse('https://api.service.platform.pichu.cluster.atomi.cloud/x'),
        ),
        isTrue,
      );
    });

    test('rejects a non-allowlisted authority', () {
      expect(
        _allowlist.allows(Uri.parse('https://evil.example.invalid/doc-b.json')),
        isFalse,
      );
    });

    test('rejects a lookalike suffix that is not a real boundary', () {
      expect(
        _allowlist.allows(Uri.parse('https://notcluster.atomi.cloud/x')),
        isFalse,
      );
    });

    test('rejects plain http even on an allowlisted authority', () {
      expect(
        _allowlist.allows(
          Uri.parse('http://api.service.platform.pichu.cluster.atomi.cloud/x'),
        ),
        isFalse,
      );
    });
  });

  test('ping URLs are derived by convention, never doc-carried', () {
    expect(
      _convention.pingUrlFor('pichu').toString(),
      'https://api.service.platform.pichu.cluster.atomi.cloud/healthz',
    );
  });

  test('a valid Doc B parses to names and metadata only', () async {
    final _StubSource source = _source();
    final Result<LandscapeSelectorDoc> result = await _client(
      source: source,
      pinger: _StubPinger(const <String, Duration?>{}),
    ).fetchDocument();

    expect(result.isSuccess, isTrue);
    final LandscapeSelectorDoc doc =
        (result as Success<LandscapeSelectorDoc>).value;
    expect(doc.platform, 'platform');
    expect(
      doc.landscapes.map((LandscapeOption o) => o.name),
      <String>['pichu', 'pikachu', 'raichu'],
    );
    expect(source.fetches, 1);
  });

  test('a non-allowlisted document URL is rejected before fetch', () async {
    final _StubSource source = _source(
      uri: 'https://evil.example.invalid/doc-b.json',
    );
    final Result<LandscapeSelectorDoc> result = await _client(
      source: source,
      pinger: _StubPinger(const <String, Duration?>{}),
    ).fetchDocument();

    expect(result, isA<Failure<LandscapeSelectorDoc>>());
    expect(
      (result as Failure<LandscapeSelectorDoc>).problem.type,
      'urn:diene:problem:endpoint-suffix-rejected',
    );
    expect(source.fetches, 0, reason: 'a bad suffix must not be fetched');
  });

  test('a derived ping URL outside the allowlist untrusts the doc', () async {
    // The document itself is allowlisted, but the convention root is not — so
    // every URL this client would actually USE fails the check.
    final Result<LandscapeSelectorDoc> result = await _client(
      source: _source(),
      pinger: _StubPinger(const <String, Duration?>{}),
      convention: const PingUrlConvention(
        platform: 'platform',
        service: 'service',
        module: 'api',
        root: 'evil.example.invalid',
      ),
    ).fetchDocument();

    expect(
      (result as Failure<LandscapeSelectorDoc>).problem.type,
      'urn:diene:problem:endpoint-suffix-rejected',
    );
  });

  test('a Doc B carrying an address is malformed', () async {
    final Result<LandscapeSelectorDoc> result = await _client(
      source: _source(
        body: _docB(
          extraOnFirst: <String, Object?>{
            'address': 'https://api.service.platform.pichu.cluster.atomi.cloud',
          },
        ),
      ),
      pinger: _StubPinger(const <String, Duration?>{}),
    ).fetchDocument();

    expect(
      (result as Failure<LandscapeSelectorDoc>).problem.type,
      'urn:diene:problem:doc-b-malformed',
    );
  });

  test('a Doc B carrying an issuer is malformed', () async {
    final Result<LandscapeSelectorDoc> result = await _client(
      source: _source(
        body: _docB(
          extraOnFirst: <String, Object?>{
            'issuer': 'https://api.lithium.platform.mew.cluster.atomi.cloud',
          },
        ),
      ),
      pinger: _StubPinger(const <String, Duration?>{}),
    ).fetchDocument();

    expect(
      (result as Failure<LandscapeSelectorDoc>).problem.type,
      'urn:diene:problem:doc-b-malformed',
      reason: 'the auth issuer is always baked, never doc-sourced',
    );
  });

  test('ping-and-pick chooses the fastest responder', () async {
    final _StubPinger pinger = _StubPinger(<String, Duration?>{
      'pichu': const Duration(milliseconds: 180),
      'pikachu': const Duration(milliseconds: 42),
      'raichu': null,
    });
    final LandscapeSelectorClient client = _client(
      source: _source(),
      pinger: pinger,
    );
    final LandscapeSelectorDoc doc =
        (await client.fetchDocument() as Success<LandscapeSelectorDoc>).value;

    final Result<String> picked = await client.pingAndPick(doc);

    expect((picked as Success<String>).value, 'pikachu');
    expect(pinger.pinged, hasLength(3));
  });

  test('no landscape answering is a recoverable failure', () async {
    final LandscapeSelectorClient client = _client(
      source: _source(),
      pinger: _StubPinger(const <String, Duration?>{}),
    );
    final LandscapeSelectorDoc doc =
        (await client.fetchDocument() as Success<LandscapeSelectorDoc>).value;

    final Result<String> picked = await client.pingAndPick(doc);

    expect(
      (picked as Failure<String>).problem.type,
      'urn:diene:problem:no-healthy-landscape',
    );
  });

  group('picker / home-claim flow', () {
    test('an existing home claim skips the picker entirely', () async {
      final MemoryHomeLandscapeClaimGateway gateway =
          MemoryHomeLandscapeClaimGateway(claim: 'pichu');
      final DocBHomeLandscapePicker picker = DocBHomeLandscapePicker(
        client: _client(
          source: _source(),
          pinger: _StubPinger(const <String, Duration?>{}),
        ),
      );

      final Result<HomeClaimResolution> result = await HomeClaimCheck(
        gateway: gateway,
        picker: picker,
      ).resolveForSignIn();

      final HomeClaimResolution resolution =
          (result as Success<HomeClaimResolution>).value;
      expect(resolution.landscape, 'pichu');
      expect(resolution.source, HomeClaimSource.existingClaim);
      expect(resolution.pickerShown, isFalse);
      expect(picker.fetches, 0, reason: 'Doc B is sign-up only');
      expect(gateway.reads, 1);
      expect(gateway.writes, 0);
    });

    test('an absent claim runs the picker and writes the claim', () async {
      final MemoryHomeLandscapeClaimGateway gateway =
          MemoryHomeLandscapeClaimGateway();
      final DocBHomeLandscapePicker picker = DocBHomeLandscapePicker(
        client: _client(
          source: _source(),
          pinger: _StubPinger(<String, Duration?>{
            'pikachu': const Duration(milliseconds: 30),
          }),
        ),
      );

      final Result<HomeClaimResolution> result = await HomeClaimCheck(
        gateway: gateway,
        picker: picker,
      ).resolveForSignIn();

      final HomeClaimResolution resolution =
          (result as Success<HomeClaimResolution>).value;
      expect(resolution.landscape, 'pikachu');
      expect(resolution.source, HomeClaimSource.picker);
      expect(resolution.pickerShown, isTrue);
      expect(picker.fetches, 1);
      expect(gateway.writes, 1);
      expect(gateway.claim, 'pikachu');
    });

    test('the claim is checked on EVERY sign-in', () async {
      final MemoryHomeLandscapeClaimGateway gateway =
          MemoryHomeLandscapeClaimGateway();
      final DocBHomeLandscapePicker picker = DocBHomeLandscapePicker(
        client: _client(
          source: _source(),
          pinger: _StubPinger(<String, Duration?>{
            'pichu': const Duration(milliseconds: 10),
          }),
        ),
      );
      final HomeClaimCheck check = HomeClaimCheck(
        gateway: gateway,
        picker: picker,
      );

      await check.resolveForSignIn();
      final Result<HomeClaimResolution> second = await check.resolveForSignIn();

      expect(gateway.reads, 2, reason: 'every sign-in re-reads the claim');
      expect(gateway.writes, 1, reason: 'the claim is written exactly once');
      expect(picker.fetches, 1, reason: 'the second sign-in skips the picker');
      expect(
        (second as Success<HomeClaimResolution>).value.pickerShown,
        isFalse,
      );
    });

    test('showing the picker with an existing claim is rejected', () {
      const HomeClaimResolution shownAnyway = HomeClaimResolution(
        landscape: 'pichu',
        source: HomeClaimSource.picker,
        pickerShown: true,
      );

      expect(
        () => HomeClaimCheck.assertPickerNotShownWithClaim(
          'pichu',
          shownAnyway,
        ),
        throwsA(isA<PickerShownWithExistingClaim>()),
      );
    });

    test('the honest resolution passes the same assertion', () async {
      final MemoryHomeLandscapeClaimGateway gateway =
          MemoryHomeLandscapeClaimGateway(claim: 'raichu');
      final Result<HomeClaimResolution> result = await HomeClaimCheck(
        gateway: gateway,
        picker: DocBHomeLandscapePicker(
          client: _client(
            source: _source(),
            pinger: _StubPinger(const <String, Duration?>{}),
          ),
        ),
      ).resolveForSignIn();

      expect(
        () => HomeClaimCheck.assertPickerNotShownWithClaim(
          'raichu',
          (result as Success<HomeClaimResolution>).value,
        ),
        returnsNormally,
      );
    });

    test('a user choice outside the document is rejected', () async {
      final DocBHomeLandscapePicker picker = DocBHomeLandscapePicker(
        client: _client(
          source: _source(),
          pinger: _StubPinger(const <String, Duration?>{}),
        ),
        onChoices: (List<LandscapeOption> options) async => 'amphoros',
      );

      final Result<String> picked = await picker.pickHomeLandscape();

      expect(
        (picked as Failure<String>).problem.type,
        'urn:diene:problem:unlisted-landscape',
      );
    });

    test('a user choice inside the document wins over the ping', () async {
      final DocBHomeLandscapePicker picker = DocBHomeLandscapePicker(
        client: _client(
          source: _source(),
          pinger: _StubPinger(<String, Duration?>{
            'pichu': const Duration(milliseconds: 5),
          }),
        ),
        onChoices: (List<LandscapeOption> options) async => 'raichu',
      );

      final Result<String> picked = await picker.pickHomeLandscape();

      expect((picked as Success<String>).value, 'raichu');
    });
  });
}
