import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Platform-channel regressions for the real iOS clipboard carrier reader and the
// callback-backed Android Install Referrer source (C0 §7). The clipboard path is
// driven through a mocked SystemChannels.platform handler, so no device is
// needed: the launch-time read takes NO consent tap, and the clear is
// conditional — it must never wipe a clipboard the user has since changed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Installs a fake platform clipboard whose contents live in [box] and records
  /// every method invoked on SystemChannels.platform.
  List<MethodCall> installClipboard(List<String?> box) {
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall call,
        ) async {
          calls.add(call);
          switch (call.method) {
            case 'Clipboard.getData':
              return box.first == null
                  ? null
                  : <String, Object?>{'text': box.first};
            case 'Clipboard.setData':
              box[0] =
                  (call.arguments as Map<Object?, Object?>)['text'] as String?;
              return null;
            default:
              return null;
          }
        });
    return calls;
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('ClipboardCarrierReader', () {
    test('reads the carrier off the clipboard on launch', () async {
      // Arrange
      final List<String?> box = <String?>['diene-carrier-token'];
      final List<MethodCall> calls = installClipboard(box);
      const ClipboardCarrierReader reader = ClipboardCarrierReader();

      // Act
      final String? carrier = await reader.read();

      // Assert — a plain read of kTextPlain, no consent prompt in the path.
      expect(carrier, 'diene-carrier-token');
      expect(calls.single.method, 'Clipboard.getData');
      expect(calls.single.arguments, Clipboard.kTextPlain);
    });

    test('reads null when the clipboard is empty', () async {
      // Arrange
      final List<String?> box = <String?>[null];
      installClipboard(box);
      const ClipboardCarrierReader reader = ClipboardCarrierReader();

      // Act + Assert
      expect(await reader.read(), isNull);
    });

    test(
      'clears the clipboard when it still equals the captured value',
      () async {
        // Arrange — trailing whitespace is trimmed before the equality check.
        final List<String?> box = <String?>['  diene-carrier-token \n'];
        final List<MethodCall> calls = installClipboard(box);
        const ClipboardCarrierReader reader = ClipboardCarrierReader();

        // Act
        await reader.clearIfEquals('diene-carrier-token');

        // Assert
        expect(box.first, '');
        expect(calls.map((MethodCall c) => c.method), <String>[
          'Clipboard.getData',
          'Clipboard.setData',
        ]);
      },
    );

    test('leaves a clipboard the user has since changed untouched', () async {
      // Arrange
      final List<String?> box = <String?>['a shopping list'];
      final List<MethodCall> calls = installClipboard(box);
      const ClipboardCarrierReader reader = ClipboardCarrierReader();

      // Act
      await reader.clearIfEquals('diene-carrier-token');

      // Assert — never destroy content the carrier does not own.
      expect(box.first, 'a shopping list');
      expect(calls.map((MethodCall c) => c.method), <String>[
        'Clipboard.getData',
      ]);
    });

    test('leaves an already-empty clipboard untouched', () async {
      // Arrange — the null-data arm of the conditional clear.
      final List<String?> box = <String?>[null];
      final List<MethodCall> calls = installClipboard(box);
      const ClipboardCarrierReader reader = ClipboardCarrierReader();

      // Act
      await reader.clearIfEquals('diene-carrier-token');

      // Assert
      expect(box.first, isNull);
      expect(calls.map((MethodCall c) => c.method), <String>[
        'Clipboard.getData',
      ]);
    });
  });

  group('CallbackInstallReferrerSource', () {
    test('delegates read and markProcessed to the injected callbacks', () async {
      // Arrange — the real plugin stays in flutter-base; this package only owns
      // the seam, so the callbacks ARE the contract.
      int reads = 0;
      int marks = 0;
      final CallbackInstallReferrerSource source =
          CallbackInstallReferrerSource(
            readReferrer: () async {
              reads += 1;
              return 'utm_source=diene&carrier=abc';
            },
            markProcessed: () async => marks += 1,
          );

      // Act
      final String? referrer = await source.read();
      await source.markProcessed();

      // Assert
      expect(referrer, 'utm_source=diene&carrier=abc');
      expect(reads, 1);
      expect(marks, 1);
    });

    test('propagates a null referrer from the platform callback', () async {
      // Arrange — no referrer means no deferred-login carrier to redeem.
      final CallbackInstallReferrerSource source =
          CallbackInstallReferrerSource(
            readReferrer: () async => null,
            markProcessed: () async {},
          );

      // Act + Assert
      expect(await source.read(), isNull);
    });
  });
}
