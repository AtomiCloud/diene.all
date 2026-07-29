import 'package:diene_flutter_base/notifications/notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

final class _MessagingGateway implements MessagingGateway {
  Future<void> Function(RemoteMessage message)? backgroundHandler;
  final List<String> topics = <String>[];

  @override
  void registerBackgroundHandler(
    Future<void> Function(RemoteMessage message) handler,
  ) {
    backgroundHandler = handler;
  }

  @override
  Future<void> subscribeToTopic(String topic) async => topics.add(topic);
}

void main() {
  test(
    'disabled notifications do not initialize Firebase or messaging',
    () async {
      final _MessagingGateway gateway = _MessagingGateway();
      int initializations = 0;

      await NotificationService(
        config: testConfig(),
        gateway: gateway,
        initializeFirebase: () async => initializations += 1,
      ).initialize();

      expect(initializations, 0);
      expect(gateway.backgroundHandler, isNull);
      expect(gateway.topics, isEmpty);
    },
  );

  test('enabled notifications wire the background handler and topic', () async {
    final _MessagingGateway gateway = _MessagingGateway();
    int initializations = 0;

    await NotificationService(
      config: testConfig(notificationsEnabled: true),
      gateway: gateway,
      initializeFirebase: () async => initializations += 1,
    ).initialize();

    expect(initializations, 1);
    expect(gateway.backgroundHandler, same(firebaseMessagingBackgroundHandler));
    expect(gateway.topics, <String>['service-updates']);
  });

  test(
    'notification router dispatches payloads to the configured handler',
    () async {
      Map<String, Object?>? received;
      NotificationRouter.handler = (Map<String, Object?> data) async {
        received = data;
      };

      await NotificationRouter.dispatch(<String, Object?>{'kind': 'refresh'});

      expect(received, <String, Object?>{'kind': 'refresh'});
    },
  );
}
