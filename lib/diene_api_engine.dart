/// diene_api_engine — the typed OA3 backend-client engine for the Dart family.
///
/// Wraps generated OpenAPI SDK calls into `Result<T, Problem>`, registers N
/// backends on the LPSM client tree with per-backend auth, retries once on a
/// hard network failure, and ships a dormant disk-cached rescue router for
/// same-landscape address failover. Client-side only; frontend-only family
/// (no OTel library — telemetry rides Faro).
library;

export 'src/bridge.dart'
    show BridgeProblems, isProblemJson, toResult, tryDecodeObject;
export 'src/client_tree.dart' show AnonymousAuth, ClientTree, IAuth;
export 'src/config.dart'
    show ApiEngineConfig, BackendConfig, LpsmCoordinate, RescueConfig;
export 'src/engine.dart' show ApiEngine, Backend;
export 'src/rescue/docs.dart' show DocA, DocC;
export 'src/rescue/router.dart'
    show RescueOutcome, RescueRouter, RescueUnavailable, Rescued;
export 'src/rescue/store.dart'
    show FileRescueStore, InMemoryRescueStore, RescueStore;
export 'src/result.dart' show Err, Ok, Problem, Result;
export 'src/transport.dart'
    show
        HttpMethod,
        HttpRequest,
        HttpResponse,
        HttpTransport,
        IoHttpTransport,
        NetworkFailure,
        Received,
        RetryOnceTransport,
        TransportOutcome;
