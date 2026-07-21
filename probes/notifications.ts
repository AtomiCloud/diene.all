import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'notifications',
  description: 'FCM initialization wires the background handler and topic.',
  command: 'nix develop .#ci -c flutter test test/notification_test.dart',
  file: 'lib/notifications/notification_service.dart',
  find: 'gateway.registerBackgroundHandler(firebaseMessagingBackgroundHandler);',
  replace: '// Background handler registration intentionally removed.',
});
