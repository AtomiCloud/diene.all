/// diene_api_engine — the typed OA3 backend-client engine for the Dart family.
///
/// Wraps generated OpenAPI SDK calls into `Result<T, Problem>`, registers N
/// backends on the LPSM client tree with per-resource auth (the auth-engine
/// `IAuth` seam), retries once on a hard network failure, and ships a dormant
/// disk-cached rescue router for same-landscape address failover. Client-side
/// only; frontend-only family (no OTel library — telemetry rides Faro).
///
/// `Result`/`Problem` are owned by `diene_result` and `IAuth`/`ResourceKey`/
/// `ResourceToken` by `diene_auth_engine`; they are re-exported here for
/// consumer convenience, never redefined.
library;

export 'package:diene_auth_engine/diene_auth_engine.dart'
    show IAuth, ResourceKey, ResourceToken;
export 'package:diene_problems/diene_problems.dart' show Problem;
export 'package:diene_result/diene_result.dart' show Err, Ok, Result;

export 'src/bridge.dart'
    show BridgeProblems, isProblemJson, toResult, tryDecodeObject;
export 'src/client_tree.dart' show ClientTree;
export 'src/config.dart'
    show ApiEngineConfig, BackendConfig, LpsmCoordinate, RescueConfig;
export 'src/engine.dart' show ApiEngine, Backend, BackendClientAdapter;
export 'src/oa3/sdk_adapter.dart' show ResultSdk;
export 'src/rescue/docs.dart' show DocA, DocC;
export 'src/rescue/router.dart'
    show RescueOutcome, RescueRouter, RescueUnavailable, Rescued;
export 'src/rescue/store.dart'
    show FileRescueStore, InMemoryRescueStore, RescueStore;
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
