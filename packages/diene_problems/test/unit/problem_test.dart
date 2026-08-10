import 'package:diene_problems/diene_problems.dart';
import 'package:test/test.dart';

void main() {
  group('Problem envelope', () {
    test(
      'toJson serializes RFC 9457 members plus the data/recoverable extensions',
      () {
        // Arrange
        const problem = Problem(
          type:
              'https://docs.example/docs/raichu/dotnet/user/api/v1/entity_not_found',
          title: 'Entity not found',
          status: 404,
          detail: 'user 42 missing',
          instance: '/user/42',
          recoverable: false,
          data: <String, Object?>{'resource': 'user', 'id': 42},
        );
        // Act
        final json = problem.toJson();
        // Assert
        expect(json['type'], problem.type);
        expect(json['title'], 'Entity not found');
        expect(json['status'], 404);
        expect(json['detail'], 'user 42 missing');
        expect(json['instance'], '/user/42');
        expect(json['recoverable'], false);
        expect(json['data'], {'resource': 'user', 'id': 42});
      },
    );

    test('fromJson round-trips a serialized envelope (data included)', () {
      const problem = Problem(
        type: 'https://h/docs/l/p/s/m/v1/id',
        title: 'Conflict',
        status: 409,
        recoverable: true,
        data: <String, Object?>{
          'nested': <String, Object?>{'a': 1},
        },
      );
      final Problem roundTripped = Problem.fromJson(problem.toJson());
      expect(roundTripped, problem);
    });

    test('fromJson applies RFC 9457 defaults for missing members', () {
      final Problem p = Problem.fromJson(const <String, Object?>{});
      expect(p.type, 'about:blank');
      expect(p.title, 'Unexpected problem');
      expect(p.status, 500);
      expect(p.recoverable, false);
      expect(p.data, <String, Object?>{});
    });

    test('fromJson coerces a non-typed data map into Map<String,Object?>', () {
      final Problem p = Problem.fromJson(<String, Object?>{
        'type': 't',
        'title': 't',
        'status': 400,
        'data': <Object?, Object?>{'k': 'v'},
      });
      expect(p.data, <String, Object?>{'k': 'v'});
    });

    test('equality is structural across all fields', () {
      const a = Problem(
        type: 't',
        title: 'T',
        status: 500,
        data: <String, Object?>{'x': 1},
      );
      const b = Problem(
        type: 't',
        title: 'T',
        status: 500,
        data: <String, Object?>{'x': 1},
      );
      const c = Problem(
        type: 't',
        title: 'T',
        status: 500,
        data: <String, Object?>{'x': 2},
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });

    test('omits nullable members when absent', () {
      const problem = Problem(type: 't', title: 'T', status: 500);
      final json = problem.toJson();
      expect(json.containsKey('detail'), isFalse);
      expect(json.containsKey('instance'), isFalse);
    });

    test('is identical to itself and unequal to a non-Problem', () {
      // Arrange
      const problem = Problem(type: 't', title: 'T', status: 500);
      final Object same = problem;
      const Object other = 't';
      // Act / Assert
      expect(problem == same, isTrue);
      expect(problem == other, isFalse);
    });

    test('toString names the type, status, and title for diagnostics', () {
      // Arrange
      const problem = Problem(
        type: 'https://h/docs/l/p/s/m/v1/x',
        title: 'T',
        status: 418,
      );
      // Act
      final rendered = problem.toString();
      // Assert
      expect(rendered, 'Problem(https://h/docs/l/p/s/m/v1/x, 418, T)');
    });
  });
}
