/**
 * Form-draft policy (product-thoughtfulness #2). The lib owns the draft STORE
 * (serialisation, malformed-JSON tolerance, the four terminal triggers); this
 * layer owns the app's KEY NAMESPACE and the decision of whether a loaded draft
 * is worth offering back to the user. Pure and node-safe so the contract is
 * unit-covered without a DOM.
 */

/** Namespace every persisted draft key under one app-owned prefix. */
export const DRAFT_KEY_PREFIX = 'diene.draft';

/** Build the namespaced storage key for a form. Blank form names are rejected. */
export const buildDraftKey = (form: string): string => {
  const trimmed = form.trim();
  if (trimmed === '') throw new Error('draft form name must not be blank');
  return `${DRAFT_KEY_PREFIX}.${trimmed}`;
};

/**
 * Offer a restore only when the draft actually carries user input: absent,
 * empty, and all-blank drafts are indistinguishable from a pristine form, so
 * prompting for them would be noise.
 */
export const shouldOfferRestore = <T extends Record<string, unknown>>(draft: T | undefined): boolean => {
  if (draft === undefined) return false;
  const values = Object.values(draft);
  if (values.length === 0) return false;
  return values.some(value =>
    typeof value === 'string' ? value.trim() !== '' : value !== undefined && value !== null,
  );
};
