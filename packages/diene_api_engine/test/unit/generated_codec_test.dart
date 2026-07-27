/// The GENERATED OA3 model codecs.
///
/// These were the largest hole in the unit ledger — `problem_details.g.dart` at
/// 0/14 lines and `user_profile.g.dart` at 4/9 — because nothing in the suite
/// ever decoded or encoded them. Generated code is still SHIPPED code: it is
/// exported through `lib/src/generated/export.dart`, so a consumer can decode a
/// `UserProfile` off the wire, and an untested codec is an untested public
/// surface.
///
/// The alternative was a `coverage:ignore-file` marker, which the sibling
/// `export.dart` already carries. That was deliberately NOT taken: masking a
/// ledger is forbidden here, and an excluded codec cannot tell you when the
/// generator's output stops round-tripping after a `swagger_parser` bump.
library;

import 'package:diene_api_engine/src/generated/export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserProfile codec', () {
    test('decodes a full payload and round-trips byte-equal', () {
      const Map<String, Object?> wire = <String, Object?>{
        'id': 'usr_42',
        'email': 'a@example.test',
        'displayName': 'Ada',
      };

      final UserProfile decoded = UserProfile.fromJson(wire);

      expect(decoded.id, 'usr_42');
      expect(decoded.email, 'a@example.test');
      expect(decoded.displayName, 'Ada');
      expect(decoded.toJson(), wire);
    });

    test('the optional displayName decodes as null and survives encoding', () {
      // The nullable branch is a separate line in the generated codec; without
      // this case the generator's null handling is unexercised.
      const Map<String, Object?> wire = <String, Object?>{
        'id': 'usr_43',
        'email': 'b@example.test',
      };

      final UserProfile decoded = UserProfile.fromJson(wire);

      expect(decoded.displayName, isNull);
      expect(decoded.toJson(), <String, Object?>{
        'id': 'usr_43',
        'email': 'b@example.test',
        'displayName': null,
      });
    });
  });

  group('ProblemDetails codec', () {
    test('decodes a full payload and round-trips byte-equal', () {
      const Map<String, Object?> wire = <String, Object?>{
        'type': 'https://docs.example.test/docs/l/p/s/m/v1/entity_not_found',
        'title': 'Entity not found',
        'status': 404,
        'detail': 'User 42 does not exist',
        'instance': '/user/42',
      };

      final ProblemDetails decoded = ProblemDetails.fromJson(wire);

      expect(decoded.type, wire['type']);
      expect(decoded.title, 'Entity not found');
      expect(decoded.status, 404);
      expect(decoded.detail, 'User 42 does not exist');
      expect(decoded.instance, '/user/42');
      expect(decoded.toJson(), wire);
    });

    test('both optional fields decode as null', () {
      const Map<String, Object?> wire = <String, Object?>{
        'type': 'urn:example:problem',
        'title': 'Bad request',
        'status': 400,
      };

      final ProblemDetails decoded = ProblemDetails.fromJson(wire);

      expect(decoded.detail, isNull);
      expect(decoded.instance, isNull);
    });

    test('a numeric status arriving as a double is coerced to int', () {
      // The generator emits `(json['status'] as num).toInt()`, so a JSON number
      // that parses as a double must not throw. This is exactly the kind of
      // generated-code behaviour an excluded file would never prove.
      final ProblemDetails decoded = ProblemDetails.fromJson(<String, Object?>{
        'type': 'urn:example:problem',
        'title': 'Server error',
        'status': 500.0,
      });

      expect(decoded.status, 500);
      expect(decoded.status, isA<int>());
    });

    test('the const constructor builds an equivalent object', () {
      // The hand-written half of the generated pair — the constructor and the
      // fields — is public surface too.
      const ProblemDetails built = ProblemDetails(
        type: 'urn:example:problem',
        title: 'Conflict',
        status: 409,
      );

      expect(built.toJson(), <String, Object?>{
        'type': 'urn:example:problem',
        'title': 'Conflict',
        'status': 409,
        'detail': null,
        'instance': null,
      });
    });
  });
}
