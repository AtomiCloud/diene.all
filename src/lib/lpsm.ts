import type { LpsmCoordinate, LpsmKey } from './types';

const coordinateFields = ['landscape', 'platform', 'service', 'module'] as const;

export type CoordinateValidation =
  | { readonly ok: true; readonly coordinate: LpsmCoordinate; readonly key: LpsmKey }
  | { readonly ok: false; readonly reason: string };

/** Validate and canonicalize all four service-tree coordinates without throwing. */
export function validateCoordinate(input: unknown): CoordinateValidation {
  if (typeof input !== 'object' || input === null || Array.isArray(input)) {
    return { ok: false, reason: 'A backend coordinate must be an object.' };
  }

  const source = input as Readonly<Record<string, unknown>>;
  const parts: string[] = [];
  for (const field of coordinateFields) {
    const value = source[field];
    if (typeof value !== 'string' || value.trim() === '') {
      return { ok: false, reason: `Backend coordinate ${field} must be a non-empty string.` };
    }
    const normalized = value.trim();
    if (normalized.includes('/')) {
      return { ok: false, reason: `Backend coordinate ${field} cannot contain '/'.` };
    }
    parts.push(normalized);
  }

  const [landscape, platform, service, module] = parts as [string, string, string, string];
  const coordinate = Object.freeze({ landscape, platform, service, module });
  return {
    ok: true,
    coordinate,
    key: `${landscape}/${platform}/${service}/${module}`,
  };
}

export function validateBaseUrl(
  input: unknown,
): { readonly ok: true; readonly baseUrl: string } | { readonly ok: false; readonly reason: string } {
  if (typeof input !== 'string') {
    return { ok: false, reason: 'Backend baseUrl must be a string from configuration.' };
  }

  try {
    const url = new URL(input);
    if (url.protocol !== 'http:' && url.protocol !== 'https:') {
      return { ok: false, reason: 'Backend baseUrl must use HTTP or HTTPS.' };
    }
    if (url.username !== '' || url.password !== '' || url.hostname === '') {
      return { ok: false, reason: 'Backend baseUrl must contain one hostname and no credentials.' };
    }
    url.hash = '';
    url.search = '';
    return { ok: true, baseUrl: url.toString().replace(/\/$/, '') };
  } catch {
    return { ok: false, reason: 'Backend baseUrl must be a valid absolute URL.' };
  }
}
