import { commandGate } from './lib/flutter.ts';

export default commandGate({
  feature: 'onboarding-phase-machine',
  description: 'Per-backend claims-first phases are independent and 409 from POST /User is create-or-ok.',
  command: 'nix develop .#ci -c flutter test test/phase_machine_test.dart',
  file: 'lib/onboarding/phase_machine.dart',
  // Treat 409 as a failure — the sabotage the goal table names for this row.
  find: 'created.status == 409;',
  replace: 'false;',
});
