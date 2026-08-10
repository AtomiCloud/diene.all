import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:diene_result/test_helper.dart';
import 'package:test/test.dart';

Result<TelemetryAttributes> _check(TelemetryAttributes? attributes) =>
    checkTelemetryAttributes(
      attributes,
      port: PortName.logging,
      operation: 'emit',
    );

void main() {
  group('checkTelemetryAttributes', () {
    test('treats a null bag as the empty bag', () {
      // Arrange & Act.
      final TelemetryAttributes accepted = expectOk(
        checkTelemetryAttributes(
          null,
          port: PortName.metrics,
          operation: 'emit',
        ),
      );

      // Assert.
      expect(accepted, isEmpty);
      expect(() => accepted['x'] = 1, throwsUnsupportedError);
    });

    test('treats an empty bag as the empty bag', () {
      // Arrange & Act.
      final TelemetryAttributes accepted = expectOk(
        checkTelemetryAttributes(
          const <String, Object?>{},
          port: PortName.metrics,
          operation: 'emit',
        ),
      );

      // Assert.
      expect(accepted, isEmpty);
    });

    test('accepts finite primitives and key-sorts the result', () {
      // Arrange.
      final TelemetryAttributes input = <String, Object?>{
        'zebra': 'z',
        'alpha': 1,
        'mid': true,
        'ratio': 1.5,
      };

      // Act.
      final TelemetryAttributes accepted = expectOk(
        checkTelemetryAttributes(
          input,
          port: PortName.logging,
          operation: 'emit',
        ),
      );

      // Assert.
      expect(accepted.keys, <String>['alpha', 'mid', 'ratio', 'zebra']);
      expect(() => accepted.clear(), throwsUnsupportedError);
    });

    test('rejects a blank key', () {
      // Arrange & Act.
      final Problem problem = expectErr(
        checkTelemetryAttributes(
          const <String, Object?>{'  ': 1},
          port: PortName.logging,
          operation: 'emit',
        ),
      );

      // Assert.
      expect(problem.data['field'], 'attributes');
      expect(problem.status, 400);
    });

    test('rejects a NUL-bearing key', () {
      // Arrange & Act.
      final Problem problem = expectErr(
        checkTelemetryAttributes(
          <String, Object?>{'na${String.fromCharCode(0)}me': 1},
          port: PortName.logging,
          operation: 'emit',
        ),
      );

      // Assert.
      expect(problem.data['field'], 'attributes');
    });

    test('rejects a non-primitive value', () {
      // Arrange & Act.
      final Problem problem = expectErr(
        checkTelemetryAttributes(
          const <String, Object?>{'nested': <String, Object?>{}},
          port: PortName.metrics,
          operation: 'emit',
        ),
      );

      // Assert.
      expect(problem.data['field'], 'attributes.nested');
    });

    test('rejects a non-finite number', () {
      // Arrange & Act.
      final Problem problem = expectErr(
        checkTelemetryAttributes(
          const <String, Object?>{'ratio': double.nan},
          port: PortName.metrics,
          operation: 'emit',
        ),
      );

      // Assert.
      expect(problem.data['field'], 'attributes.ratio');
    });

    test('rejects a null value', () {
      // Arrange & Act & Assert.
      expect(
        expectErr(
          _check(const <String, Object?>{'absent': null}),
        ).data['field'],
        'attributes.absent',
      );
    });
  });

  test('emptyTelemetryAttributes is unmodifiable', () {
    // Arrange & Act & Assert.
    expect(() => emptyTelemetryAttributes['x'] = 1, throwsUnsupportedError);
  });
}
