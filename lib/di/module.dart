/// Module / DI port (argon feature port 5 of 5).
///
/// The app is composed from [AppModule]s: each module declares the bindings it
/// owns, a [ModuleRegistry] collects them, and the resulting [ModuleContainer]
/// resolves dependencies for the widget tree — the "provider resolves modules"
/// gate.
///
/// Why a container and not ambient singletons: the stateless-OOP-and-DI standard
/// requires collaborators to arrive through constructors. The container is the
/// single place that *builds* those constructor arguments; nothing reaches into
/// it from inside domain code. Widgets reach it through `provider` at the tree
/// root via [ModuleScope] / [ModuleContext.module].
///
/// Every failure mode is a `Result`, never a throw:
/// * duplicate binding across two modules → [ModuleProblemTypes.duplicateBinding]
///   (a silent last-one-wins override is how DI wiring rots);
/// * resolving a type nothing bound → [ModuleProblemTypes.missingBinding];
/// * a binding that transitively resolves itself → [ModuleProblemTypes.circularDependency]
///   (reported instead of overflowing the stack).
///
/// Resolution is lazy and memoised: a factory runs at most once per container, so
/// a module can bind an expensive client without paying for it in a screen that
/// never asks.
library;

import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// Problem type URNs emitted by this port.
abstract final class ModuleProblemTypes {
  static const String duplicateBinding =
      'urn:diene:problem:module-duplicate-binding';
  static const String missingBinding =
      'urn:diene:problem:module-missing-binding';
  static const String circularDependency =
      'urn:diene:problem:module-circular-dependency';
}

/// Builds an instance of a bound type, resolving its own collaborators from the
/// container it is being built into.
typedef ModuleFactory<T extends Object> = T Function(ModuleContainer container);

/// The surface a module registers its bindings through.
abstract interface class ModuleBinder {
  /// Bind [factory] as the provider of `T`.
  ///
  /// Binding the same `T` twice — from the same module or a different one — is a
  /// wiring defect and is reported by [ModuleRegistry.build].
  void bind<T extends Object>(ModuleFactory<T> factory);
}

/// One composable unit of the application graph.
abstract interface class AppModule {
  /// Stable module name, used in diagnostics and duplicate reports.
  String get name;

  /// Register everything this module owns.
  void register(ModuleBinder binder);
}

final class _Binding {
  const _Binding({required this.moduleName, required this.factory});

  final String moduleName;
  final ModuleFactory<Object> factory;
}

final class _Binder implements ModuleBinder {
  _Binder(this.moduleName, this.bindings, this.duplicates);

  final String moduleName;
  final Map<Type, _Binding> bindings;
  final List<String> duplicates;

  @override
  void bind<T extends Object>(ModuleFactory<T> factory) {
    final _Binding? existing = bindings[T];
    if (existing != null) {
      duplicates.add('$T (${existing.moduleName} and $moduleName)');
      return;
    }
    bindings[T] = _Binding(
      moduleName: moduleName,
      factory: (ModuleContainer container) => factory(container),
    );
  }
}

/// Collects [AppModule]s and builds the resolved [ModuleContainer].
final class ModuleRegistry {
  const ModuleRegistry(this.modules);

  final List<AppModule> modules;

  /// The registered module names, in registration order.
  List<String> get moduleNames =>
      modules.map((AppModule module) => module.name).toList(growable: false);

  /// Run every module's registration and build the container.
  ///
  /// Returns `Err` [ModuleProblemTypes.duplicateBinding] if two modules bind
  /// the same type; the container is never half-built.
  Result<ModuleContainer> build() {
    final Map<Type, _Binding> bindings = <Type, _Binding>{};
    final List<String> duplicates = <String>[];
    for (final AppModule module in modules) {
      module.register(_Binder(module.name, bindings, duplicates));
    }
    if (duplicates.isNotEmpty) {
      return Err<ModuleContainer>(
        Problem(
          type: ModuleProblemTypes.duplicateBinding,
          title: 'Duplicate module binding',
          status: 500,
          detail: 'Bound more than once: ${duplicates.join('; ')}.',
          data: <String, Object?>{'duplicates': duplicates},
        ),
      );
    }
    return Ok<ModuleContainer>(ModuleContainer._(bindings));
  }
}

/// The resolved application graph.
final class ModuleContainer {
  ModuleContainer._(this._bindings);

  final Map<Type, _Binding> _bindings;
  final Map<Type, Object> _instances = <Type, Object>{};
  final Set<Type> _resolving = <Type>{};

  /// The bound types, for diagnostics and tests.
  Iterable<Type> get boundTypes => _bindings.keys;

  /// Whether `T` has a binding.
  bool isBound<T extends Object>() => _bindings.containsKey(T);

  /// The module that bound `T`, or null when unbound.
  String? providerOf<T extends Object>() => _bindings[T]?.moduleName;

  /// Resolve `T`, building it (once) if needed.
  ///
  /// Total: an unbound type or a dependency cycle comes back as `Err`.
  Result<T> resolve<T extends Object>() {
    final Object? existing = _instances[T];
    if (existing != null) {
      return Ok<T>(existing as T);
    }
    final _Binding? binding = _bindings[T];
    if (binding == null) {
      return Err<T>(
        Problem(
          type: ModuleProblemTypes.missingBinding,
          title: 'Missing module binding',
          status: 500,
          detail:
              'Nothing bound $T. Bound types: '
              '${_bindings.keys.join(', ')}.',
          data: <String, Object?>{'requested': '$T'},
        ),
      );
    }
    if (!_resolving.add(T)) {
      return Err<T>(
        Problem(
          type: ModuleProblemTypes.circularDependency,
          title: 'Circular module dependency',
          status: 500,
          detail: 'Resolving $T re-entered itself via ${_resolving.join(' -> ')}.',
          data: <String, Object?>{
            'cycle': _resolving.map((Type type) => '$type').toList(),
          },
        ),
      );
    }
    try {
      final Object instance = binding.factory(this);
      _instances[T] = instance;
      return Ok<T>(instance as T);
    } finally {
      _resolving.remove(T);
    }
  }

  /// Resolve `T` or throw a [StateError].
  ///
  /// For composition-root call sites that cannot meaningfully continue without
  /// the dependency; domain code uses [resolve] and folds the `Result`.
  T require<T extends Object>() => resolve<T>().match<T>(
    ok: (T value) => value,
    err: (Problem problem) =>
        throw StateError('${problem.title}: ${problem.detail}'),
  );
}

/// Exposes a built [ModuleContainer] to the widget tree via `provider`.
final class ModuleScope extends StatelessWidget {
  const ModuleScope({required this.container, required this.child, super.key});

  final ModuleContainer container;
  final Widget child;

  @override
  Widget build(BuildContext context) => Provider<ModuleContainer>.value(
    value: container,
    child: child,
  );
}

/// Widget-side resolution against the nearest [ModuleScope].
extension ModuleContext on BuildContext {
  /// The container provided by the nearest [ModuleScope].
  ModuleContainer get modules => read<ModuleContainer>();

  /// Resolve `T` from the nearest [ModuleScope].
  Result<T> module<T extends Object>() => modules.resolve<T>();
}
