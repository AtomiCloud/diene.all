import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'form-lifecycle',
  description: 'A draft persists live, restores, and is cleared on submit/reset, with live per-field validation.',
  command:
    "nix develop .#ci -c flutter test test/widget_test.dart --plain-name 'persistent field validates live, restores, and clears its draft'",
  file: 'lib/widgets/persistent_form.dart',
  // Retain the draft after clearing — the goal table's "retain the draft after
  // successful submit" sabotage, anchored to `clear()` rather than to
  // `submitted()`. `submitted()` is a one-line delegation to `clear()` that NO
  // landed test invokes, so a sabotage there would fail to redden and report a
  // false not-caught. Dropping the removal here leaves the stored draft behind
  // while the field still looks cleared to the user.
  find: 'await widget.preferences.remove(widget.storageKey);',
  replace: '// Draft removal intentionally skipped.',
});
