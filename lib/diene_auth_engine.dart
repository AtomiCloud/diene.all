/// Frontend auth engine for the AtomiCloud Diene Dart family.
///
/// Ships: Logto flows + per-resource tokens, the multi-backend claims-first
/// onboarding phase machine, the deferred-login mobile client (carrier +
/// redeem), returnTo deeplink continuation, the engine-owned config block
/// schema, and the sign-up-only Doc B landscape selector.
///
/// Dart is frontend-only — there is NO otel surface here; telemetry rides Faro
/// through flutter-base.
library;

export 'src/auth/auth_provider.dart';
export 'src/auth/auth_seam.dart';
export 'src/auth/claims.dart';
export 'src/auth/session_controller.dart';
export 'src/config/auth_engine_config.dart';
export 'src/contracts/problem.dart';
export 'src/contracts/result.dart';
export 'src/deferred/carrier.dart';
export 'src/deferred/deferred_login.dart';
export 'src/deferred/redeem_client.dart';
export 'src/home/home_claim.dart';
export 'src/home/landscape_selector.dart';
export 'src/logto/clipboard_carrier_source.dart';
export 'src/logto/http_app_handoff_api.dart';
export 'src/logto/http_landscape_source.dart';
export 'src/logto/logto_auth_provider.dart';
export 'src/onboarding/backend_registry.dart';
export 'src/onboarding/onboarding_phase.dart';
export 'src/onboarding/user_directory.dart';
export 'src/returnto/return_to.dart';
export 'src/sign_in_coordinator.dart';
export 'src/tokens/resource_key.dart';
export 'src/tokens/session_tokens.dart';
export 'src/tokens/token_lifetimes.dart';
