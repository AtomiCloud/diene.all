import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

void main() {
  final Problem problem = Problem(
    type: 'about:blank',
    title: 'Missing value',
    status: 404,
  );

  group('Option', () {
    test(
      'constructors, nullable conversion, matching, native, and text work',
      () {
        // Arrange
        const Option<String> some = Option<String>.some('lapras');
        const Option<String> none = Option<String>.none();

        // Act
        final Option<String> fromValue = Option<String>.fromNullable('pichu');
        final Option<String> fromNull = Option<String>.fromNullable(null);
        final String someMatch = some.match(
          some: (String value) => 'some:$value',
          none: () => 'none',
        );
        final String noneMatch = none.match(
          some: (String value) => 'some:$value',
          none: () => 'none',
        );

        // Assert
        expect(some.isSome, isTrue);
        expect(some.isNone, isFalse);
        expect(none.isSome, isFalse);
        expect(none.isNone, isTrue);
        expect(fromValue.unwrap(), 'pichu');
        expect(fromNull.isNone, isTrue);
        expect(someMatch, 'some:lapras');
        expect(noneMatch, 'none');
        expect(some.native(), 'lapras');
        expect(none.native(), isNull);
        expect(some.toString(), 'Some(lapras)');
        expect(none.toString(), 'None');
      },
    );

    test('map and andThen transform only Some', () {
      // Arrange
      const Option<int> some = Option<int>.some(21);
      const Option<int> none = Option<int>.none();

      // Act
      final Option<int> mapped = some.map((int value) => value * 2);
      final Option<int> skippedMap = none.map((int value) => value * 2);
      final Option<String> chained = some.andThen(
        (int value) => Option<String>.some('$value!'),
      );
      final Option<String> skippedChain = none.andThen(
        (int value) => Option<String>.some('$value!'),
      );

      // Assert
      expect(mapped.unwrap(), 42);
      expect(skippedMap.isNone, isTrue);
      expect(chained.unwrap(), '21!');
      expect(skippedChain.isNone, isTrue);
    });

    test('unwrap family returns values, fallbacks, and rich misuse errors', () {
      // Arrange
      const Option<int> some = Option<int>.some(21);
      const Option<int> none = Option<int>.none();
      var fallbackCalls = 0;

      // Act
      final int someFallback = some.unwrapOr(0);
      final int noneFallback = none.unwrapOr(0);
      final int someComputed = some.unwrapOrElse(() {
        fallbackCalls += 1;
        return 1;
      });
      final int noneComputed = none.unwrapOrElse(() {
        fallbackCalls += 1;
        return 42;
      });

      // Assert
      expect(some.unwrap(), 21);
      expect(someFallback, 21);
      expect(noneFallback, 0);
      expect(someComputed, 21);
      expect(noneComputed, 42);
      expect(fallbackCalls, 1);
      expect(
        () => none.unwrap(),
        throwsA(
          isA<UnwrapError>()
              .having(
                (UnwrapError value) => value.monad,
                'monad',
                MonadKind.option,
              )
              .having((UnwrapError value) => value.expected, 'expected', 'Some')
              .having((UnwrapError value) => value.actual, 'actual', 'None')
              .having((UnwrapError value) => value.payload, 'payload', isNull),
        ),
      );
    });

    test('Result bridges preserve Some and None semantics', () {
      // Arrange
      const Option<int> some = Option<int>.some(21);
      const Option<int> none = Option<int>.none();
      final Option<Problem> someProblem = Option<Problem>.some(problem);
      const Option<Problem> noProblem = Option<Problem>.none();

      // Act
      final Result<int> someOk = some.okOr(problem);
      final Result<int> noneErr = none.okOr(problem);
      final Result<String> someMapped = some.asResult(
        some: (int value) => Result<String>.ok('$value!'),
        none: () => Result<String>.err(problem),
      );
      final Result<String> noneMapped = none.asResult(
        some: (int value) => Result<String>.ok('$value!'),
        none: () => Result<String>.err(problem),
      );
      final Result<int> problemErr = someProblem.errOr(21);
      final Result<int> problemOk = noProblem.errOr(21);

      // Assert
      expect(someOk.unwrap(), 21);
      expect(noneErr.unwrapErr(), same(problem));
      expect(someMapped.unwrap(), '21!');
      expect(noneMapped.unwrapErr(), same(problem));
      expect(problemErr.unwrapErr(), same(problem));
      expect(problemOk.unwrap(), 21);
    });

    test('serial round-trips Some, nullable Some, and None', () {
      // Arrange
      const Option<int> some = Option<int>.some(21);
      const Option<String?> nullableSome = Option<String?>.some(null);
      const Option<int> none = Option<int>.none();

      // Act
      final OptionSerial someWire = some.serial(
        encodeSome: (int value) => <String, Object?>{'value': value},
      );
      final OptionSerial nullableWire = nullableSome.serial();
      final OptionSerial noneWire = none.serial();
      final Option<int> decodedSome = Option<int>.fromSerial(
        someWire,
        decodeSome: (Object? value) =>
            (value! as Map<Object?, Object?>)['value']! as int,
      );
      final Option<String?> decodedNullable = Option<String?>.fromSerial(
        nullableWire,
        decodeSome: (Object? value) => value as String?,
      );
      final Option<int> decodedNone = Option<int>.fromSerial(
        noneWire,
        decodeSome: (Object? value) => value! as int,
      );

      // Assert
      expect(decodedSome.unwrap(), 21);
      expect(decodedNullable.isSome, isTrue);
      expect(decodedNullable.unwrap(), isNull);
      expect(decodedNone.isNone, isTrue);
      expect(() => noneWire.add(1), throwsUnsupportedError);
    });

    test('malformed Option wire values fail before decoding payloads', () {
      // Arrange
      final List<OptionSerial> malformed = <OptionSerial>[
        <Object?>['some'],
        <Object?>['wat', 1],
        <Object?>[1, 1],
        <Object?>['none', 'not-null'],
      ];

      // Act
      Option<int> decode(OptionSerial serial) => Option<int>.fromSerial(
        serial,
        decodeSome: (Object? value) => value! as int,
      );

      // Assert
      for (final OptionSerial wire in malformed) {
        expect(() => decode(wire), throwsFormatException);
      }
    });
  });
}
