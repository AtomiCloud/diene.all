import 'package:test/test.dart';

import '../support.dart';

void main() {
  group('AppSettings equality', () {
    test('keeps control characters within their original tag element', () {
      final AppSettings splitAfterFirstTag = AppSettings(
        name: 'app',
        retries: 1,
        tags: const <String>['a\u0000b', 'c'],
      );
      final AppSettings splitBeforeSecondTag = AppSettings(
        name: 'app',
        retries: 1,
        tags: const <String>['a', 'b\u0000c'],
      );
      final AppSettings equivalent = AppSettings(
        name: 'app',
        retries: 1,
        tags: const <String>['a\u0000b', 'c'],
      );

      expect(splitAfterFirstTag, isNot(equals(splitBeforeSecondTag)));
      expect(splitBeforeSecondTag, isNot(equals(splitAfterFirstTag)));
      expect(splitAfterFirstTag, equals(equivalent));
      expect(splitAfterFirstTag.hashCode, equivalent.hashCode);
    });
  });
}
