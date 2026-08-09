import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'rebrand-guard',
  description: 'Brand, ASO, and auth values remain config-driven.',
  command: 'nix develop .#ci -c ./scripts/validate/rebrand.sh',
  file: 'lib/app.dart',
  find: 'title: widget.config.branding.appName,',
  replace: "title: 'Diene Mobile',",
});
