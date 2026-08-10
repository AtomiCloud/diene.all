/// R-E14 wire-id CONTRACT-VARIANCE test.
///
/// The frozen C0 release `c0-fixtures-r2` still carries KEBAB problem ids in its
/// SAMPLE values (`entity-not-found`, `validation-error`) while R-E14 amended
/// C0 §7 so the WIRE id is snake_case (`entity_not_found`) — the spelling the
/// published `@atomicloud/diene.problems@1.0.0` builder enforces with
/// `^[a-z][a-z0-9_]*$`. Five independent sources agree on snake_case (R-E14, C0
/// §14 prose, the Problem CRD regex, the zinc seed, and the published Bun
/// builder); the fixture is the lone dissenter, so a corrected fixture round is
/// owed AT THE RELEASE OWNER (R-E8a — fixed once, inherited by merge) and this
/// leaf never rewrites the release bytes.
///
/// Per the lead's ratified 2026-07-26 disposition this test PINS THE PAIR: it
/// fails if the release bytes stop carrying the variance (the fixture round
/// landed — drop the normalization) and it fails if this package stops enforcing
/// R-E14 (the regression the ruling exists to prevent). Either side changing
/// silently is what the test forbids.
library;

import 'dart:convert';
import 'dart:io';

import 'package:diene_problems/diene_problems.dart';
import 'package:test/test.dart';

const String _casePath = '../../contracts/c0/cases/problem.json';

Map<String, Object?> _map(Object? value) =>
    Map<String, Object?>.from(value! as Map<dynamic, dynamic>);

List<Object?> _list(Object? value) =>
    List<Object?>.from(value! as List<dynamic>);

/// Every problem id the frozen release samples, in stable order.
List<String> _releaseSampleIds() {
  final Map<String, Object?> cases = _map(
    _map(jsonDecode(File(_casePath).readAsStringSync()))['cases'],
  );
  return <String>[
    ..._list(
      _map(cases['typeUri'])['valid'],
    ).map((Object? vector) => _map(_map(vector)['segments'])['id']! as String),
    ..._list(
      _map(cases['catalogEntry'])['samples'],
    ).map((Object? sample) => _map(sample)['id']! as String),
  ];
}

void main() {
  group('R-E14 wire-id enforcement (this package)', () {
    test('the builder enforces the published snake_case wire-id regex', () {
      // Arrange.
      const ErrorPortal portal = ErrorPortal.localError;

      // Act / Assert. Snake_case is accepted…
      expect(
        problemTypeUri(portal: portal, version: 'v1', id: 'entity_not_found'),
        endsWith('/v1/entity_not_found'),
      );

      // …and every non-conforming spelling is rejected at the boundary.
      for (final String rejected in <String>[
        'entity-not-found', // pre-R-E14 kebab
        'EntityNotFound', // definition/factory name, never the wire id
        'entity.not.found',
        '1entity',
        '_entity',
        'entity not found',
        '',
      ]) {
        expect(
          () => problemTypeUri(portal: portal, version: 'v1', id: rejected),
          throwsA(isA<InvalidProblemTypeSegmentError>()),
          reason: '$rejected must not be a legal wire id',
        );
      }
    });

    test('the enforced pattern is exactly the published bun pattern', () {
      expect(problemWireIdPattern.pattern, r'^[a-z][a-z0-9_]*$');
    });

    test('every shipped generic problem id is a legal wire id', () {
      for (final ProblemType type in GenericProblems.all) {
        expect(
          problemWireIdPattern.hasMatch(type.id),
          isTrue,
          reason: '${type.id} violates R-E14',
        );
      }
    });

    test('the shipped local-error id is a legal wire id', () async {
      // Arrange.
      final _CapturingSink sink = _CapturingSink();

      // Act.
      final Problem problem = await LocalError(
        sink,
      ).wrap(StateError('boom'), StackTrace.empty);

      // Assert.
      final String id = problem.type.split('/').last;
      expect(problemWireIdPattern.hasMatch(id), isTrue);
      expect(id, 'local_error');
      expect(sink.captured.single, problem);
    });
  });

  group('frozen-release variance (the release owner owes r3)', () {
    test('the release still samples KEBAB ids — the variance is real', () {
      // Arrange.
      final List<String> ids = _releaseSampleIds();

      // Assert. If this fails the corrected fixture round has landed: delete
      // the normalization in the conformance test and delete this group.
      expect(ids, isNotEmpty);
      expect(
        ids.any((String id) => id.contains('-')),
        isTrue,
        reason:
            'the frozen release no longer carries the pre-R-E14 kebab variance; '
            'a corrected round landed — drop r14WireId and this test',
      );
      expect(
        ids.every((String id) => !problemWireIdPattern.hasMatch(id)),
        isTrue,
        reason: 'the release samples are uniformly pre-R-E14',
      );
    });

    test('normalization is exactly kebab → underscore, nothing else', () {
      for (final String id in _releaseSampleIds()) {
        expect(r14WireId(id), id.replaceAll('-', '_'));
        expect(problemWireIdPattern.hasMatch(r14WireId(id)), isTrue);
      }
      // Already-conforming ids pass through untouched.
      expect(r14WireId('app_handoff_expired'), 'app_handoff_expired');
    });

    test('the release TEMPLATE is consumed verbatim, never normalized', () {
      // Arrange. The template is what the fixture IS authoritative for.
      final Map<String, Object?> cases = _map(
        _map(jsonDecode(File(_casePath).readAsStringSync()))['cases'],
      );

      // Assert.
      expect(cases['typeUriTemplate'], c0ProblemContract.typeUriTemplate);
      expect(
        (cases['typeUriTemplate']! as String).contains('-'),
        isFalse,
        reason: 'the template itself carries no kebab tokens to normalize',
      );
    });
  });
}

final class _CapturingSink implements ErrorSink {
  final List<Problem> captured = <Problem>[];

  @override
  Future<void> capture(Problem problem) async => captured.add(problem);
}
