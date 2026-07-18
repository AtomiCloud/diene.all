import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'click-reaction',
  description: 'Async controls disable, show pending state, settle, and avoid double fire.',
  command:
    "nix develop .#ci -c flutter test test/widget_test.dart --plain-name 'AsyncButton disables, shows pending, and avoids double-fire'",
  file: 'lib/widgets/async_button.dart',
  find: ': FilledButton(onPressed: _pending ? null : _run, child: content),',
  replace: ': FilledButton(onPressed: _run, child: content),',
});
