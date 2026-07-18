import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../config/app_config.dart';

typedef NotificationHandler = Future<void> Function(Map<String, Object?> data);
typedef FirebaseInitializer = Future<void> Function();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await NotificationRouter.dispatch(message.data);
}

final class NotificationRouter {
  NotificationRouter._();

  static NotificationHandler handler = (Map<String, Object?> data) async {};

  static Future<void> dispatch(Map<String, Object?> data) => handler(data);
}

abstract interface class MessagingGateway {
  void registerBackgroundHandler(
    Future<void> Function(RemoteMessage message) handler,
  );
  Future<void> subscribeToTopic(String topic);
}

final class FirebaseMessagingGateway implements MessagingGateway {
  const FirebaseMessagingGateway();

  @override
  void registerBackgroundHandler(
    Future<void> Function(RemoteMessage message) handler,
  ) {
    FirebaseMessaging.onBackgroundMessage(handler);
  }

  @override
  Future<void> subscribeToTopic(String topic) =>
      FirebaseMessaging.instance.subscribeToTopic(topic);
}

final class NotificationService {
  NotificationService({
    required this.config,
    required this.gateway,
    FirebaseInitializer? initializeFirebase,
  }) : _initializeFirebase = initializeFirebase ?? _initializeDefaultFirebase;

  final AppConfig config;
  final MessagingGateway gateway;
  final FirebaseInitializer _initializeFirebase;

  Future<void> initialize() async {
    if (!config.notifications.enabled) {
      return;
    }
    await _initializeFirebase();
    gateway.registerBackgroundHandler(firebaseMessagingBackgroundHandler);
    await gateway.subscribeToTopic(config.notifications.topic);
  }

  static Future<void> _initializeDefaultFirebase() async {
    await Firebase.initializeApp();
  }
}
