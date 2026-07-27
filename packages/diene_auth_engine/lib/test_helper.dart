/// Dependency-light TestHelper sub-library for `diene_auth_engine`.
///
/// Fakes, builders, and plain-throw assertions ONLY — NO test-framework deps
/// (no `test` / `matcher` / mocking packages), so importing it adds nothing to a
/// consumer's production dependency graph.
library;

export 'src/test_helper/assertions.dart';
export 'src/test_helper/builders.dart';
export 'src/test_helper/fakes.dart';
