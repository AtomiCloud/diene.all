import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/test_helper.dart';
import 'package:test/test.dart';

MetricRecord _sample({
  String name = 'requests.total',
  MetricKind kind = MetricKind.counter,
  num value = 1,
  String? unit,
  DateTime? timestamp,
  Map<String, Object?> attributes = const <String, Object?>{},
}) => MetricRecord(
  timestamp: timestamp ?? DateTime.utc(2026),
  name: name,
  kind: kind,
  value: value,
  unit: unit,
  attributes: attributes,
);

void main() {
  group('MetricRecord', () {
    test('copies and freezes its attributes', () {
      // Arrange.
      final Map<String, Object?> attributes = <String, Object?>{'route': '/a'};

      // Act.
      final MetricRecord record = _sample(
        name: 'latency',
        kind: MetricKind.histogram,
        value: 12.5,
        unit: 'ms',
        attributes: attributes,
      );
      attributes['injected'] = true;

      // Assert.
      expect(record.attributes, <String, Object?>{'route': '/a'});
      expect(() => record.attributes.remove('route'), throwsUnsupportedError);
      expect(record.unit, 'ms');
      expect(record.toString(), 'MetricRecord(latency, histogram, 12.5)');
      expect(MetricKind.values, hasLength(3));
    });

    test('defaults to no unit and no attributes', () {
      // Arrange & Act.
      final MetricRecord record = _sample();

      // Assert.
      expect(record.unit, isNull);
      expect(record.attributes, isEmpty);
      expect(record.timestamp, DateTime.utc(2026));
    });
  });

  group('checkMetricRecord', () {
    test('accepts a well-formed counter sample', () {
      // Arrange.
      final MetricRecord record = _sample(
        attributes: <String, Object?>{'ok': true},
      );

      // Act & Assert.
      expect(expectOk(checkMetricRecord(record)), same(record));
    });

    test('accepts a negative gauge', () {
      // Arrange & Act & Assert.
      expect(
        expectOk(
          checkMetricRecord(
            _sample(name: 'queue.depth', kind: MetricKind.gauge, value: -3),
          ),
        ).value,
        -3,
      );
    });

    test('rejects a name that breaks the shared pattern', () {
      // Arrange & Act.
      final Problem problem = expectErr(
        checkMetricRecord(_sample(name: '1bad')),
      );

      // Assert.
      expect(problem.data['field'], 'name');
      expect(problem.data['port'], 'metrics');
    });

    test('rejects a non-UTC timestamp', () {
      // Arrange & Act & Assert.
      expect(
        expectErr(
          checkMetricRecord(_sample(timestamp: DateTime(2026, 7, 25))),
        ).data['field'],
        'timestamp',
      );
    });

    test('rejects a non-finite value', () {
      // Arrange & Act & Assert.
      expect(
        expectErr(
          checkMetricRecord(
            _sample(kind: MetricKind.gauge, value: double.infinity),
          ),
        ).title,
        'Metric value must be finite',
      );
    });

    test('rejects a negative counter', () {
      // Arrange & Act & Assert.
      expect(
        expectErr(checkMetricRecord(_sample(value: -1))).title,
        'Counter samples must not be negative',
      );
    });

    test('rejects a blank unit', () {
      // Arrange & Act & Assert.
      expect(
        expectErr(checkMetricRecord(_sample(unit: ' '))).data['field'],
        'unit',
      );
    });

    test('rejects invalid attributes through the shared telemetry rule', () {
      // Arrange & Act & Assert.
      expect(
        expectErr(
          checkMetricRecord(
            _sample(attributes: <String, Object?>{'bad': Object()}),
          ),
        ).data['field'],
        'attributes.bad',
      );
    });
  });

  test('metricNamePattern accepts the documented shape', () {
    // Arrange & Act & Assert.
    expect(metricNamePattern.hasMatch('http.server/duration-ms'), isTrue);
    expect(metricNamePattern.hasMatch('has space'), isFalse);
  });
}
