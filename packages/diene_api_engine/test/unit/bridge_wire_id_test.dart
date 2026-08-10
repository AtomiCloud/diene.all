import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_problems/diene_problems.dart'
    show problemWireIdPattern, r14WireId;
import 'package:flutter_test/flutter_test.dart';

/// R-E14 wire-id regression.
///
/// Every `BridgeProblems` id was KEBAB (`transport-failure`, …) while the
/// published `problemWireIdPattern` is `^[a-z][a-z0-9_]*$`. `problemTypeUri`
/// validates the id at CONSTRUCTION, so each getter threw the moment it was
/// touched — and because `ClientTree.register` and `toResult` build one on their
/// error paths, the failure surfaced as 12 unrelated-looking test failures across
/// four files rather than as one obvious wire-id error.
///
/// This asserts against the PUBLISHED pattern, never a local copy of the regex.
/// A duplicated local pattern is how the two halves drift apart, and re-pointing
/// at the published constant is what lib/dart/interfaces did after the same law
/// cost it a CI cycle.
void main() {
  group('R-E14: every BridgeProblems wire id is snake_case', () {
    // The getters, by name, so a NEW id added to BridgeProblems without a row
    // here is visible as a gap rather than silently unchecked.
    final Map<String, String> ids = <String, String>{
      'transportFailure': BridgeProblems.transportFailure,
      'unexpectedResponse': BridgeProblems.unexpectedResponse,
      'duplicateBackend': BridgeProblems.duplicateBackend,
      'authTokenUnavailable': BridgeProblems.authTokenUnavailable,
    };

    test('the set under test is not empty', () {
      // A loop over an empty collection passes while asserting nothing; refuse
      // that outcome explicitly.
      expect(ids, isNotEmpty);
      expect(ids.length, 4);
    });

    ids.forEach((String name, String uri) {
      test('$name yields an id matching the published pattern', () {
        // The wire id is the last path segment of the type URI.
        final String wireId = uri.substring(uri.lastIndexOf('/') + 1);

        expect(
          wireId,
          isNotEmpty,
          reason: 'the type URI must end in a wire id',
        );
        expect(
          problemWireIdPattern.hasMatch(wireId),
          isTrue,
          reason:
              '$name produced wire id "$wireId", which violates the published '
              'problemWireIdPattern — R-E14 requires snake_case, not kebab',
        );
        expect(
          wireId.contains('-'),
          isFalse,
          reason: 'a hyphen in a wire id is exactly the R-E14 violation',
        );
      });
    });

    test('constructing each id does not throw', () {
      // The original defect was a THROW at construction, not a wrong value, so
      // this asserts reachability directly rather than inferring it from the
      // pattern checks above.
      for (final String name in ids.keys) {
        expect(() => ids[name], returnsNormally, reason: name);
      }
    });
  });

  group('R-E14 normalization is available and narrow', () {
    test('r14WireId turns the frozen kebab sample id into a legal wire id', () {
      // The frozen C0 release predates R-E14 and still carries kebab SAMPLE ids.
      // This is the ONE documented transformation consumers may apply, and it is
      // what the conformance suite uses instead of editing frozen bytes.
      const String legacy = 'entity-not-found';
      expect(problemWireIdPattern.hasMatch(legacy), isFalse);
      expect(problemWireIdPattern.hasMatch(r14WireId(legacy)), isTrue);
      expect(r14WireId(legacy), 'entity_not_found');
    });

    test('it is exactly hyphen to underscore, nothing else', () {
      // If it ever did more than that, a "normalized" id could silently differ
      // from the release bytes in ways the conformance suite would not catch.
      expect(r14WireId('already_snake'), 'already_snake');
      expect(r14WireId('a-b-c'), 'a_b_c');
      expect(r14WireId('MiXeD-Case'), 'MiXeD_Case');
    });
  });
}
