/// Query-parameter state: the url-as-state half of the routing surface.
///
/// A shareable link must reproduce the viewer's state EXACTLY. That means the
/// encode/decode pair is lossless in both directions for every field that
/// belongs in a link, and that dropping one field from the encoding is a
/// detectable defect rather than a silent degradation — omitting one filter is
/// the sabotage the query-state gate catches.
///
/// Drafts and transient UI state deliberately do NOT live here (see the screen
/// standard): only state that benefits another viewer is encoded.
library;

import 'package:collection/collection.dart';

/// How a list-valued filter is encoded into a single query parameter.
const String _listSeparator = ',';

/// The shareable state of the signal list screen.
///
/// Every field here round-trips through [toQueryParameters] /
/// [SignalQuery.fromQueryParameters]. Adding a field means adding it to BOTH,
/// and [SignalQuery.encodedFields] names them so a test can assert the
/// encoding covers the whole record rather than whichever fields someone
/// remembered.
final class SignalQuery {
  const SignalQuery({
    this.text = '',
    this.severities = const <SignalSeverity>[],
    this.landscape,
    this.sort = SignalSort.newestFirst,
    this.page = 1,
    this.unresolvedOnly = false,
  });

  /// Read state out of a link. Unknown values fall back to the default rather
  /// than throwing — a stale or hand-edited link should still open.
  factory SignalQuery.fromQueryParameters(Map<String, String> parameters) {
    final String? rawSeverity = parameters[_keySeverity];
    final String? rawSort = parameters[_keySort];
    final String? rawPage = parameters[_keyPage];
    return SignalQuery(
      text: parameters[_keyText]?.trim() ?? '',
      severities: rawSeverity == null || rawSeverity.isEmpty
          ? const <SignalSeverity>[]
          : rawSeverity
                .split(_listSeparator)
                .map(
                  (String token) => SignalSeverity.values.firstWhereOrNull(
                    (SignalSeverity value) => value.wire == token.trim(),
                  ),
                )
                .whereType<SignalSeverity>()
                .toList(),
      landscape: _emptyToNull(parameters[_keyLandscape]),
      sort:
          SignalSort.values.firstWhereOrNull(
            (SignalSort value) => value.wire == rawSort,
          ) ??
          SignalSort.newestFirst,
      page: _positiveOr(int.tryParse(rawPage ?? ''), 1),
      unresolvedOnly: parameters[_keyUnresolved] == 'true',
    );
  }

  static const String _keyText = 'q';
  static const String _keySeverity = 'severity';
  static const String _keyLandscape = 'landscape';
  static const String _keySort = 'sort';
  static const String _keyPage = 'page';
  static const String _keyUnresolved = 'unresolved';

  /// Every parameter key this record encodes. The query-state gate asserts the
  /// encoding of a fully-populated record covers exactly this set, so a filter
  /// dropped from [toQueryParameters] turns it red.
  static const List<String> encodedFields = <String>[
    _keyText,
    _keySeverity,
    _keyLandscape,
    _keySort,
    _keyPage,
    _keyUnresolved,
  ];

  /// Free-text filter.
  final String text;

  /// Selected severities; empty means "no severity filter".
  final List<SignalSeverity> severities;

  /// Landscape filter; `null` means "every landscape".
  final String? landscape;

  /// Result ordering.
  final SignalSort sort;

  /// 1-based page number.
  final int page;

  /// Whether resolved signals are hidden.
  final bool unresolvedOnly;

  /// True when nothing is filtered — the bare route with no parameters.
  bool get isDefault =>
      text.isEmpty &&
      severities.isEmpty &&
      landscape == null &&
      sort == SignalSort.newestFirst &&
      page == 1 &&
      !unresolvedOnly;

  /// Encode into query parameters. A field at its default is OMITTED rather
  /// than written out, so the canonical link for the unfiltered view is the
  /// bare path (the search-bar standard: an empty query removes the parameter).
  Map<String, String> toQueryParameters() => <String, String>{
    if (text.isNotEmpty) _keyText: text,
    if (severities.isNotEmpty)
      _keySeverity: severities
          .map((SignalSeverity value) => value.wire)
          .join(_listSeparator),
    if (landscape != null && landscape!.isNotEmpty) _keyLandscape: landscape!,
    if (sort != SignalSort.newestFirst) _keySort: sort.wire,
    if (page != 1) _keyPage: '$page',
    if (unresolvedOnly) _keyUnresolved: 'true',
  };

  /// The full location (path + query) this state corresponds to. This is the
  /// string that is safe to share.
  String toLocation(String path) {
    final Map<String, String> parameters = toQueryParameters();
    return Uri(
      path: path,
      queryParameters: parameters.isEmpty ? null : parameters,
    ).toString();
  }

  SignalQuery copyWith({
    String? text,
    List<SignalSeverity>? severities,
    String? landscape,
    bool clearLandscape = false,
    SignalSort? sort,
    int? page,
    bool? unresolvedOnly,
  }) => SignalQuery(
    text: text ?? this.text,
    severities: severities ?? this.severities,
    landscape: clearLandscape ? null : (landscape ?? this.landscape),
    sort: sort ?? this.sort,
    page: page ?? this.page,
    unresolvedOnly: unresolvedOnly ?? this.unresolvedOnly,
  );

  @override
  String toString() =>
      'SignalQuery(text=$text, severities=$severities, '
      'landscape=$landscape, sort=$sort, page=$page, '
      'unresolvedOnly=$unresolvedOnly)';

  @override
  bool operator ==(Object other) =>
      other is SignalQuery &&
      other.text == text &&
      const ListEquality<SignalSeverity>().equals(
        other.severities,
        severities,
      ) &&
      other.landscape == landscape &&
      other.sort == sort &&
      other.page == page &&
      other.unresolvedOnly == unresolvedOnly;

  @override
  int get hashCode => Object.hash(
    text,
    const ListEquality<SignalSeverity>().hash(severities),
    landscape,
    sort,
    page,
    unresolvedOnly,
  );
}

/// Signal severity, with an explicit wire token so renaming the Dart value
/// cannot silently break every shared link.
enum SignalSeverity {
  info('info'),
  warning('warning'),
  critical('critical');

  const SignalSeverity(this.wire);

  final String wire;
}

/// Result ordering, with an explicit wire token for the same reason.
enum SignalSort {
  newestFirst('newest'),
  oldestFirst('oldest'),
  severityFirst('severity');

  const SignalSort(this.wire);

  final String wire;
}

String? _emptyToNull(String? value) {
  final String? trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

int _positiveOr(int? value, int fallback) =>
    value == null || value < 1 ? fallback : value;
