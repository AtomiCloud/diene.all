import 'package:diene_flutter_base/core/local_error.dart';
import 'package:diene_flutter_base/core/problem_catalog.dart';
import 'package:diene_flutter_base/core/result.dart';
import 'package:diene_flutter_base/core/temporal.dart';
import 'package:flutter_test/flutter_test.dart';

final class _RecordingSink implements ErrorSink {
  Problem? captured;

  @override
  Future<void> capture(Problem problem) async => captured = problem;
}

void main() {
  test('Result folds success and RFC-shaped Problem round-trips', () {
    const Result<int> result = Success<int>(42);
    final int value = result.fold<int>(
      onSuccess: (int item) => item,
      onFailure: (Problem _) => -1,
    );
    const Problem problem = Problem(
      type: 'urn:test',
      title: 'Conflict',
      status: 409,
      detail: 'Already exists',
      recoverable: true,
    );

    expect(value, 42);
    expect(result.isSuccess, isTrue);
    expect(Problem.fromJson(problem.toJson()).toJson(), problem.toJson());
  });

  test(
    'LocalError wraps message and stack then propagates to the sink',
    () async {
      final _RecordingSink sink = _RecordingSink();
      final StackTrace stack = StackTrace.current;
      final Problem problem = await LocalError(
        sink,
      ).wrap(StateError('broken locally'), stack);

      expect(problem.title, 'Local Error');
      expect(problem.data['message'], contains('broken locally'));
      expect(problem.data['stackTrace'], stack.toString());
      expect(sink.captured, same(problem));
    },
  );

  test(
    'catalog classifies known responses and reports uncatalogued ones',
    () async {
      Problem? unexpected;
      final ProblemCatalog catalog = ProblemCatalog(
        endpoints: const <String, Map<int, ProblemCatalogEntry>>{
          '/user/me': <int, ProblemCatalogEntry>{
            404: ProblemCatalogEntry(
              type: 'urn:test:not-onboarded',
              title: 'Not onboarded',
              status: 404,
              recoverable: true,
            ),
          },
        },
        onUnexpected: (Problem problem) async => unexpected = problem,
      );

      final Problem known = await catalog.classify(
        endpoint: '/user/me',
        status: 404,
      );
      final Problem unknown = await catalog.classify(
        endpoint: '/user/me',
        status: 418,
      );

      expect(known.recoverable, isTrue);
      expect(unknown.status, 500);
      expect(unknown.data['upstreamStatus'], 418);
      expect(unexpected, same(unknown));
    },
  );

  test('Temporal C0 codecs round-trip every supported wire value', () {
    const TemporalCodec codec = TemporalCodec();

    expect(
      codec.decodeDate(
        codec.encodeDate(const LocalDate(year: 2026, month: 7, day: 18)),
      ),
      const LocalDate(year: 2026, month: 7, day: 18),
    );
    expect(
      codec.decodeTime(
        codec.encodeTime(const LocalTime(hour: 1, minute: 2, second: 3)),
      ),
      const LocalTime(hour: 1, minute: 2, second: 3),
    );
    expect(
      codec.decodeInstant(
        codec.encodeInstant(UtcInstant(DateTime.utc(2026, 7, 18))),
      ),
      UtcInstant(DateTime.utc(2026, 7, 18)),
    );
    expect(
      codec.decodeDuration(codec.encodeDuration(const IsoDuration('PT10M'))),
      const IsoDuration('PT10M'),
    );
    expect(
      codec.decodeTimezone(codec.encodeTimezone(IanaTimezone.parse('Etc/UTC'))),
      IanaTimezone.parse('Etc/UTC'),
    );
  });
}
