import 'dart:convert';

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

/// META TIER — fixture/builder invariants. Built fixtures must satisfy the
/// package's own guards and round-trips.
void main() {
  test('problemFixture round-trips through Problem.fromJson unchanged', () {
    final Problem built = problemFixture(
      type: 'urn:diene:problem:inv',
      status: 400,
      data: const <String, Object?>{'a': 1},
    );
    final Problem back = Problem.fromJson(built.toJson());
    expect(back.type, built.type);
    expect(back.status, built.status);
    expect(back.data['a'], 1);
  });

  test('problemResponse body passes isProblemJson', () {
    final Received response = problemResponse(problemFixture(status: 409));
    final Object? json = jsonDecode(response.response.body);
    expect(isProblemJson(json), isTrue);
    expect(response.response.status, 409);
  });

  test('okJson body decodes to a JSON object', () {
    final Received response = okJson(<String, Object?>{'k': 'v'});
    expect(tryDecodeObject(response.response.body)?['k'], 'v');
  });

  test('nonProblemJson body is JSON but NOT a problem', () {
    final Received response = nonProblemJson(<String, Object?>{
      'message': 'x',
    }, status: 400);
    expect(isProblemJson(jsonDecode(response.response.body)), isFalse);
  });

  test('networkFailure builder is a NetworkFailure outcome', () {
    expect(networkFailure('x'), isA<NetworkFailure>());
  });
}
