/// R-E14 wire-id CONTRACT-VARIANCE test for `diene_interfaces`.
///
/// The frozen C0 release `c0-fixtures-r2` still carries KEBAB problem ids in its
/// SAMPLE values (`entity-not-found`) while R-E14 amended C0 so the WIRE id is
/// snake_case — the spelling the published `problemTypeUri` builder in
/// `package:diene_problems` enforces with `^[a-z][a-z0-9_]*$`. The fixture is the
/// lone dissenter, so a corrected fixture round (r3) is owed AT THE RELEASE OWNER
/// under R-E8a (fixed once there, inherited by merge) and this leaf never rewrites
/// the release bytes — `c0_problem_test.dart` normalizes with the release owner's
/// own published `r14WireId` helper instead.
///
/// Per the lead's ratified 2026-07-26 disposition, already applied by the
/// published sibling `lib/dart/problems`, this test PINS THE PAIR: it fails if the
/// release bytes stop carrying the variance (r3 landed — delete the normalization
/// in `c0_problem_test.dart` and delete this file) and it fails if this package
/// stops emitting R-E14-legal wire ids (the regression the ruling exists to
/// prevent). Either side changing silently is what this test forbids.
library;

import 'dart:convert';
import 'dart:io';

import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:test/test.dart';

/// The frozen release case file, read through the same relative path the
/// generated projection is derived from.
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
    test('every shipped PortErrorCode wire id is a legal wire id', () {
      for (final PortErrorCode code in PortErrorCode.values) {
        expect(
          problemWireIdPattern.hasMatch(code.wireId),
          isTrue,
          reason:
              '${code.name} ships wire id "${code.wireId}", violating R-E14',
        );
      }
    });

    test('every composed seam id is a legal wire id', () {
      // The id is composed as `<port>_<wireId>`, so a legal port and a legal
      // code can still compose an ILLEGAL id if the separator regresses to a
      // hyphen. This asserts the composed value, which is what ships.
      for (final PortName port in PortName.values) {
        for (final PortErrorCode code in PortErrorCode.values) {
          final String id = portProblem(
            port: port,
            code: code,
            operation: 'probe',
            message: 'probe',
          ).type.split('/').last;
          expect(
            problemWireIdPattern.hasMatch(id),
            isTrue,
            reason: 'composed id "$id" violates R-E14',
          );
        }
      }
    });

    test('the enforced pattern is exactly the published pattern', () {
      expect(problemWireIdPattern.pattern, r'^[a-z][a-z0-9_]*$');
    });
  });

  group('frozen-release variance (the release owner owes r3)', () {
    test('the release still samples KEBAB ids — the variance is real', () {
      // Arrange.
      final List<String> ids = _releaseSampleIds();

      // Assert. If this fails, the corrected fixture round has landed: delete
      // the r14WireId normalization in c0_problem_test.dart and delete this file.
      expect(ids, isNotEmpty);
      expect(
        ids.any((String id) => id.contains('-')),
        isTrue,
        reason:
            'the frozen release no longer carries the pre-R-E14 kebab variance; '
            'a corrected round landed — drop the normalization and this file',
      );
    });

    test('normalization is exactly kebab to underscore, nothing else', () {
      for (final String id in _releaseSampleIds()) {
        expect(r14WireId(id), id.replaceAll('-', '_'));
        expect(problemWireIdPattern.hasMatch(r14WireId(id)), isTrue);
      }
      // Already-conforming ids pass through untouched.
      expect(r14WireId('entity_not_found'), 'entity_not_found');
    });
  });
}
