import 'package:diene_flutter_base/routing/query_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fully-populated state: EVERY field non-default. Used to prove the encoding
/// covers the whole record — a field dropped from `toQueryParameters` shows up
/// here as a missing key, which is the "omit one filter" sabotage.
const SignalQuery _full = SignalQuery(
  text: 'disk pressure',
  severities: <SignalSeverity>[SignalSeverity.warning, SignalSeverity.critical],
  landscape: 'lapras',
  sort: SignalSort.severityFirst,
  page: 3,
  unresolvedOnly: true,
);

void main() {
  group('a shareable link reproduces state exactly', () {
    test('a fully-populated state round-trips with every field intact', () {
      final Map<String, String> encoded = _full.toQueryParameters();
      final SignalQuery restored = SignalQuery.fromQueryParameters(encoded);

      // Field by field, not just == , so a failure names WHICH filter was lost.
      expect(restored.text, _full.text);
      expect(restored.severities, _full.severities);
      expect(restored.landscape, _full.landscape);
      expect(restored.sort, _full.sort);
      expect(restored.page, _full.page);
      expect(restored.unresolvedOnly, _full.unresolvedOnly);
      expect(restored, _full);
    });

    test('the encoding covers every declared field', () {
      // The gate's core assertion. `encodedFields` names the whole record, so a
      // filter that exists on the class but never reaches the query string is
      // caught here rather than discovered by a viewer whose link half-worked.
      final Map<String, String> encoded = _full.toQueryParameters();

      expect(
        encoded.keys.toSet(),
        SignalQuery.encodedFields.toSet(),
        reason:
            'every field of a fully-populated state must be encoded; a missing '
            'key means a filter is dropped from shareable links',
      );
    });

    test('omitting one filter from the link loses that filter', () {
      // Proves the round trip is actually sensitive: drop ONE key from the
      // encoding and the restored state differs. If this passed, the assertions
      // above would be unfalsifiable.
      final Map<String, String> encoded = _full.toQueryParameters()
        ..remove('severity');
      final SignalQuery restored = SignalQuery.fromQueryParameters(encoded);

      expect(restored.severities, isEmpty);
      expect(restored, isNot(_full));
    });

    for (final String field in SignalQuery.encodedFields) {
      test('dropping "$field" from the link changes the restored state', () {
        // Every field individually. A field whose removal changes nothing is a
        // field that is not really carrying state.
        final Map<String, String> encoded = _full.toQueryParameters()
          ..remove(field);

        expect(
          SignalQuery.fromQueryParameters(encoded),
          isNot(_full),
          reason: '$field appears to be encoded but carries no state',
        );
      });
    }

    test('the round trip survives a full location string', () {
      // The realistic path: state -> URL -> parsed URL -> state, exactly what
      // happens when a link is pasted into another device.
      final String location = _full.toLocation('/home');
      final Uri parsed = Uri.parse(location);

      expect(SignalQuery.fromQueryParameters(parsed.queryParameters), _full);
    });

    test('a location keeps its path', () {
      expect(_full.toLocation('/home'), startsWith('/home?'));
    });

    test('text with spaces and symbols survives the location round trip', () {
      const SignalQuery query = SignalQuery(text: 'two words & more');

      final Uri parsed = Uri.parse(query.toLocation('/home'));

      expect(
        SignalQuery.fromQueryParameters(parsed.queryParameters).text,
        'two words & more',
      );
    });
  });

  group('defaults are omitted so the canonical link is minimal', () {
    test('the default state encodes to nothing', () {
      expect(const SignalQuery().toQueryParameters(), isEmpty);
    });

    test('the default state is the bare path with no query', () {
      // Search-bar standard: an empty query REMOVES the parameter rather than
      // leaving a trailing "?q=".
      expect(const SignalQuery().toLocation('/home'), '/home');
    });

    test('the default state reports itself as default', () {
      expect(const SignalQuery().isDefault, isTrue);
      expect(_full.isDefault, isFalse);
    });

    test('an empty query string restores the default state', () {
      expect(
        SignalQuery.fromQueryParameters(const <String, String>{}),
        const SignalQuery(),
      );
    });

    for (final (String label, SignalQuery query, String key)
        in <(String, SignalQuery, String)>[
          ('text', SignalQuery(text: 'x'), 'q'),
          (
            'severities',
            SignalQuery(severities: <SignalSeverity>[SignalSeverity.info]),
            'severity',
          ),
          ('landscape', SignalQuery(landscape: 'pichu'), 'landscape'),
          ('sort', SignalQuery(sort: SignalSort.oldestFirst), 'sort'),
          ('page', SignalQuery(page: 2), 'page'),
          ('unresolvedOnly', SignalQuery(unresolvedOnly: true), 'unresolved'),
        ]) {
      test('only $label is encoded when only $label is set', () {
        expect(query.toQueryParameters().keys, <String>[key]);
      });
    }
  });

  group('a stale or hand-edited link still opens', () {
    // A shared link outlives the code that made it. Unknown values fall back to
    // the default rather than throwing, because a viewer pasting an old link
    // should see the app, not a crash.
    test('an unknown severity token is dropped, keeping the known ones', () {
      final SignalQuery restored = SignalQuery.fromQueryParameters(
        const <String, String>{'severity': 'warning,made-up,critical'},
      );

      expect(restored.severities, <SignalSeverity>[
        SignalSeverity.warning,
        SignalSeverity.critical,
      ]);
    });

    test('an unknown sort token falls back to the default', () {
      expect(
        SignalQuery.fromQueryParameters(const <String, String>{
          'sort': 'sideways',
        }).sort,
        SignalSort.newestFirst,
      );
    });

    test('a non-numeric page falls back to page 1', () {
      expect(
        SignalQuery.fromQueryParameters(const <String, String>{
          'page': 'abc',
        }).page,
        1,
      );
    });

    test('a zero or negative page falls back to page 1', () {
      expect(
        SignalQuery.fromQueryParameters(const <String, String>{
          'page': '0',
        }).page,
        1,
      );
      expect(
        SignalQuery.fromQueryParameters(const <String, String>{
          'page': '-4',
        }).page,
        1,
      );
    });

    test('an empty severity value yields no severities', () {
      expect(
        SignalQuery.fromQueryParameters(const <String, String>{
          'severity': '',
        }).severities,
        isEmpty,
      );
    });

    test('whitespace-only text and landscape normalize away', () {
      final SignalQuery restored = SignalQuery.fromQueryParameters(
        const <String, String>{'q': '   ', 'landscape': '  '},
      );

      expect(restored.text, isEmpty);
      expect(restored.landscape, isNull);
      expect(restored.isDefault, isTrue);
    });

    test('anything other than "true" means unresolvedOnly is off', () {
      expect(
        SignalQuery.fromQueryParameters(const <String, String>{
          'unresolved': 'yes',
        }).unresolvedOnly,
        isFalse,
      );
    });
  });

  group('wire tokens are stable', () {
    // Renaming a Dart enum value must not silently invalidate every link ever
    // shared, so the wire tokens are asserted explicitly.
    test('severity tokens', () {
      expect(
        SignalSeverity.values.map((SignalSeverity s) => s.wire).toList(),
        <String>['info', 'warning', 'critical'],
      );
    });

    test('sort tokens', () {
      expect(SignalSort.values.map((SignalSort s) => s.wire).toList(), <String>[
        'newest',
        'oldest',
        'severity',
      ]);
    });
  });

  group('copyWith', () {
    test('replaces only the named field', () {
      final SignalQuery next = _full.copyWith(page: 9);

      expect(next.page, 9);
      expect(next.text, _full.text);
      expect(next.severities, _full.severities);
    });

    test('clears the landscape explicitly', () {
      // A nullable field needs an explicit clear: passing null cannot be
      // distinguished from "not supplied".
      expect(_full.copyWith(clearLandscape: true).landscape, isNull);
      expect(_full.copyWith().landscape, _full.landscape);
    });
  });

  group('value semantics', () {
    test('equal states are equal and hash alike', () {
      const SignalQuery a = SignalQuery(
        text: 'x',
        severities: <SignalSeverity>[SignalSeverity.info],
      );
      const SignalQuery b = SignalQuery(
        text: 'x',
        severities: <SignalSeverity>[SignalSeverity.info],
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('severity ORDER is part of identity', () {
      const SignalQuery a = SignalQuery(
        severities: <SignalSeverity>[
          SignalSeverity.info,
          SignalSeverity.warning,
        ],
      );
      const SignalQuery b = SignalQuery(
        severities: <SignalSeverity>[
          SignalSeverity.warning,
          SignalSeverity.info,
        ],
      );

      expect(a, isNot(b));
    });
  });
}
