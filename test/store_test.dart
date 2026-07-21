import 'dart:io';

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:test/test.dart';

void main() {
  group('FileRescueStore (dart:io disk seam)', () {
    test('round-trips, sanitises keys, and deletes', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'diene_rescue_',
      );
      addTearDown(() => dir.delete(recursive: true));
      final FileRescueStore store = FileRescueStore(dir);

      expect(await store.read('missing'), isNull);
      await store.write('docc.platform.lapras', 'v1');
      expect(await store.read('docc.platform.lapras'), 'v1');

      // Keys with slashes/colons are sanitised to a safe filename.
      await store.write('pin.lapras/platform:svc', 'https://x');
      expect(await store.read('pin.lapras/platform:svc'), 'https://x');

      await store.delete('docc.platform.lapras');
      expect(await store.read('docc.platform.lapras'), isNull);
      // Deleting a missing key is a no-op.
      await store.delete('docc.platform.lapras');
    });
  });

  group('InMemoryRescueStore', () {
    test('seeds, writes, reads, deletes', () async {
      final InMemoryRescueStore store = InMemoryRescueStore(<String, String>{
        'a': '1',
      });
      expect(await store.read('a'), '1');
      await store.write('b', '2');
      expect(await store.read('b'), '2');
      await store.delete('a');
      expect(await store.read('a'), isNull);
    });
  });
}
