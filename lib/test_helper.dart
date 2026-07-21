/// diene_api_engine test helpers — a DEPENDENCY-LIGHT sub-library
/// (`package:diene_api_engine/test_helper.dart`). It ships fakes, plain-throw
/// assertions, and builders with NO test-framework dependency, so it adds
/// nothing to a consumer's production graph.
library;

export 'src/test_helper/assertions.dart'
    show check, expectErr, expectOk, expectProblemType;
export 'src/test_helper/builders.dart'
    show
        networkFailure,
        nonJsonResponse,
        nonProblemJson,
        okJson,
        problemFixture,
        problemResponse;
export 'src/test_helper/fakes.dart'
    show
        FakeAuth,
        FakeClock,
        FakeHttpTransport,
        FakeRescueStore,
        HangingTransport,
        noJitter,
        noSleep;
