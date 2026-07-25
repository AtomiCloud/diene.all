import type { AllowlistConfig } from '@atomicloud/diene.frontend-utils/discovery';
import type { PickerConfig } from '@/config';

/**
 * The BAKED endpoint-suffix allowlist derived from the picker config. There is
 * no doc signing: this allowlist is what replaces it, so the derivation is the
 * security boundary and lives here — pure, node-safe, and unit-covered with an
 * accept/reject table rather than buried inside a browser adapter.
 *
 * Rescue roots are intentionally EMPTY for this template: its rescue is
 * redeploy, not client routing, so no exact-host escape hatch is granted.
 */
export const pickerAllowlist = (picker: PickerConfig): AllowlistConfig => ({
  suffixes: picker.allowedSuffixes.filter(suffix => suffix.trim() !== ''),
  rescueRoots: [],
});

/**
 * The convention root used to derive ping URLs: the first allowed suffix with
 * its leading dot removed, so derived hosts are inside the allowlist by
 * construction.
 */
export const pickerPingRoot = (picker: PickerConfig): string =>
  picker.allowedSuffixes[0]?.replace(/^\./, '') ?? 'cluster.atomi.cloud';
