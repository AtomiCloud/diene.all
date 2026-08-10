/// `diene_e2e` — the L-dart family version train and consumer test harness.
///
/// This primary library is the family **version train**: the single package a
/// consumer (flutter-base's E4 swap-in) depends on to get a coherent set of the
/// seven L-dart libraries at once, instead of pinning each individually. It
/// re-exports the runtime API of every member.
///
/// It also exposes the pure-value **contract models** this package owns — the
/// C0 §7 app-handoff (deferred-login) wire shapes and carrier codec — which the
/// shared fixture and consumer journeys build and parse.
///
/// The dependency-light TEST harness (stub server, journey drivers, the shared
/// app-handoff fixture, plain-throw assertions, and the member test-helper
/// re-exports) lives on the separate `package:diene_e2e/test_helper.dart` entry
/// point, so importing it never adds test-framework deps to a consumer's
/// production graph.
///
/// ## Version-train re-exports
///
/// Every member below is consumed as a PUBLISHED HOSTED package from pub.dev —
/// never a path dependency, a workspace dependency, or a `dependency_override`.
/// The pinned versions, and the reasoning behind each pin (newest-satisfying as
/// the retraction control, and why `diene_problems` is `^0.1.1` rather than
/// `^0.1.0`), are documented on `dependencies:` in this package's
/// `pubspec.yaml`.
///
/// All seven members are published, so all seven are wired. Listed in family-DAG
/// order — `diene_problems` is the family root, per R-E32.
///
/// **These re-exports need no `hide`/`show` disambiguation, and that is a
/// measured fact rather than an assumption.** A duplicate-name audit across the
/// seven published archives, honouring each barrel's own `show` clauses, found
/// **121 public declarations and ZERO colliding names**. The same detector run
/// against the `test_helper.dart` surfaces returns two collisions (`FakeAuth`,
/// `expectOk`) — that positive control is what makes the zero here a
/// measurement instead of an empty result. `test_helper.dart` therefore carries
/// explicit disambiguation and this file deliberately does not.
///
/// Note that `diene_api_engine`'s own barrel already re-exports a narrow slice
/// of three siblings (`show IAuth, ResourceKey, ResourceToken` from
/// auth-engine, `show Problem` from problems, `show Err, Ok, Result` from
/// result). Dart resolves a name re-exported by two paths to the same
/// declaration without conflict, so those overlaps are harmless; the other six
/// members re-export no siblings at all.
library;

export 'package:diene_api_engine/diene_api_engine.dart';
export 'package:diene_auth_engine/diene_auth_engine.dart';
export 'package:diene_config/diene_config.dart';
export 'package:diene_core_utils/diene_core_utils.dart';
export 'package:diene_interfaces/diene_interfaces.dart';
export 'package:diene_problems/diene_problems.dart';
export 'package:diene_result/diene_result.dart';

export 'src/app_handoff/carrier.dart';
export 'src/app_handoff/wire.dart';
