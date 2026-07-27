import 'package:diene_flutter_base/core/result.dart';
import 'package:diene_flutter_base/di/module.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Clock {
  const _Clock(this.zone);

  final String zone;
}

final class _Repository {
  const _Repository(this.clock);

  final _Clock clock;
}

final class _Coordinator {
  const _Coordinator(this.repository);

  final _Repository repository;
}

/// Binds the leaf dependency; counts builds so laziness/memoisation is provable.
final class _CoreModule implements AppModule {
  _CoreModule({this.zone = 'UTC'});

  final String zone;
  int clockBuilds = 0;

  @override
  String get name => 'core';

  @override
  void register(ModuleBinder binder) {
    binder.bind<_Clock>((ModuleContainer container) {
      clockBuilds += 1;
      return _Clock(zone);
    });
  }
}

/// Binds the mid and top layers, resolving their own collaborators.
final class _DataModule implements AppModule {
  const _DataModule();

  @override
  String get name => 'data';

  @override
  void register(ModuleBinder binder) {
    binder.bind<_Repository>(
      (ModuleContainer container) => _Repository(container.require<_Clock>()),
    );
    binder.bind<_Coordinator>(
      (ModuleContainer container) =>
          _Coordinator(container.require<_Repository>()),
    );
  }
}

/// Re-binds a type the core module already owns.
final class _ConflictingModule implements AppModule {
  const _ConflictingModule();

  @override
  String get name => 'conflicting';

  @override
  void register(ModuleBinder binder) {
    binder.bind<_Clock>((ModuleContainer container) => const _Clock('Mars'));
  }
}

/// Binds a type whose factory resolves itself.
final class _CyclicModule implements AppModule {
  const _CyclicModule();

  @override
  String get name => 'cyclic';

  @override
  void register(ModuleBinder binder) {
    binder.bind<_Repository>(
      (ModuleContainer container) => container.require<_Repository>(),
    );
  }
}

ModuleContainer _expectContainer(Result<ModuleContainer> result) =>
    result.fold<ModuleContainer>(
      onSuccess: (ModuleContainer value) => value,
      onFailure: (Problem problem) =>
          fail('expected the container to build, got ${problem.detail}'),
    );

Problem _expectProblem<T extends Object>(Result<T> result) =>
    result.fold<Problem>(
      onSuccess: (T value) => fail('expected a failure, got $value'),
      onFailure: (Problem problem) => problem,
    );

void main() {
  group('module / DI port', () {
    test('a provider resolves every registered module binding', () {
      final _CoreModule core = _CoreModule(zone: 'Asia/Singapore');
      final ModuleRegistry registry = ModuleRegistry(<AppModule>[
        core,
        const _DataModule(),
      ]);
      final ModuleContainer container = _expectContainer(registry.build());

      expect(registry.moduleNames, <String>['core', 'data']);
      expect(container.boundTypes.toSet(), <Type>{
        _Clock,
        _Repository,
        _Coordinator,
      });
      expect(container.providerOf<_Clock>(), 'core');
      expect(container.providerOf<_Coordinator>(), 'data');

      final _Coordinator coordinator = container.require<_Coordinator>();
      expect(coordinator.repository.clock.zone, 'Asia/Singapore');
    });

    test('resolution is lazy and memoised (each factory runs at most once)', () {
      final _CoreModule core = _CoreModule();
      final ModuleContainer container = _expectContainer(
        ModuleRegistry(<AppModule>[core, const _DataModule()]).build(),
      );

      expect(core.clockBuilds, 0, reason: 'nothing built until asked');

      final _Clock first = container.require<_Clock>();
      final _Repository repository = container.require<_Repository>();
      final _Clock second = container.require<_Clock>();

      expect(core.clockBuilds, 1);
      expect(second, same(first));
      expect(repository.clock, same(first));
      expect(container.require<_Repository>(), same(repository));
    });

    test('a MISSING registration is a Failure naming the requested type', () {
      final ModuleContainer container = _expectContainer(
        ModuleRegistry(<AppModule>[_CoreModule()]).build(),
      );

      expect(container.isBound<_Clock>(), isTrue);
      expect(container.isBound<_Repository>(), isFalse);
      expect(container.providerOf<_Repository>(), isNull);

      final Problem problem = _expectProblem(container.resolve<_Repository>());
      expect(problem.type, 'urn:diene:problem:module-missing-binding');
      expect(problem.status, 500);
      expect(problem.data['requested'], '_Repository');
      expect(problem.detail, contains('_Clock'));
    });

    test('a BROKEN registration inside a factory surfaces as a Failure', () {
      // _DataModule without _CoreModule: _Repository's own dependency is unbound.
      final ModuleContainer container = _expectContainer(
        ModuleRegistry(<AppModule>[const _DataModule()]).build(),
      );

      expect(
        () => container.require<_Repository>(),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('Missing module binding'),
          ),
        ),
      );
    });

    test('a DUPLICATE binding refuses to build the container', () {
      final Problem problem = _expectProblem(
        ModuleRegistry(<AppModule>[
          _CoreModule(),
          const _ConflictingModule(),
        ]).build(),
      );

      expect(problem.type, 'urn:diene:problem:module-duplicate-binding');
      expect(problem.detail, contains('_Clock'));
      expect(problem.detail, contains('core'));
      expect(problem.detail, contains('conflicting'));
      expect(
        (problem.data['duplicates'] as List<Object?>?)?.length,
        1,
        reason: 'last-one-wins overrides must never be silent',
      );
    });

    test('a CIRCULAR dependency is reported, not a stack overflow', () {
      final ModuleContainer container = _expectContainer(
        ModuleRegistry(<AppModule>[const _CyclicModule()]).build(),
      );

      expect(
        () => container.require<_Repository>(),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('Circular module dependency'),
          ),
        ),
      );
    });

    test('an empty registry builds an empty container', () {
      final ModuleContainer container = _expectContainer(
        const ModuleRegistry(<AppModule>[]).build(),
      );

      expect(container.boundTypes, isEmpty);
      expect(
        _expectProblem(container.resolve<_Clock>()).type,
        'urn:diene:problem:module-missing-binding',
      );
    });

    testWidgets('ModuleScope resolves modules through the widget tree', (
      WidgetTester tester,
    ) async {
      final ModuleContainer container = _expectContainer(
        ModuleRegistry(<AppModule>[
          _CoreModule(zone: 'Europe/Berlin'),
          const _DataModule(),
        ]).build(),
      );
      String? resolvedZone;
      String? missingProblemType;

      await tester.pumpWidget(
        ModuleScope(
          container: container,
          child: Builder(
            builder: (BuildContext context) {
              resolvedZone = context
                  .module<_Coordinator>()
                  .fold<String>(
                    onSuccess: (_Coordinator coordinator) =>
                        coordinator.repository.clock.zone,
                    onFailure: (Problem problem) => 'unresolved',
                  );
              missingProblemType = context
                  .module<_UnboundThing>()
                  .fold<String>(
                    onSuccess: (_UnboundThing _) => 'unexpectedly resolved',
                    onFailure: (Problem problem) => problem.type,
                  );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(resolvedZone, 'Europe/Berlin');
      expect(
        missingProblemType,
        'urn:diene:problem:module-missing-binding',
        reason: 'the widget seam reports misses instead of throwing',
      );
      expect(
        tester.element(find.byType(SizedBox)).modules,
        same(container),
      );
    });
  });
}

final class _UnboundThing {
  const _UnboundThing();
}
