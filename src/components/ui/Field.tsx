'use client';

import { clsx } from 'clsx';
import { useId, useMemo, useRef, useState } from 'react';
import type { z } from 'zod';

/**
 * Rule-defaulting form field: `autocomplete`, `inputmode`, and `enterkeyhint`
 * are REQUIRED props (a consumer cannot ship a field without them), and live
 * per-field validation runs debounced zod-on-change (product-thoughtfulness
 * #3) against the supplied schema.
 */
export function Field({
  label,
  value,
  onChange,
  schema,
  autoComplete,
  inputMode,
  enterKeyHint,
  type = 'text',
  debounceMs = 300,
}: {
  readonly label: string;
  readonly value: string;
  readonly onChange: (value: string) => void;
  readonly schema: z.ZodType<string>;
  readonly autoComplete: string;
  readonly inputMode: 'text' | 'email' | 'tel' | 'url' | 'numeric' | 'decimal' | 'search';
  readonly enterKeyHint: 'enter' | 'done' | 'go' | 'next' | 'previous' | 'search' | 'send';
  readonly type?: string;
  readonly debounceMs?: number;
}) {
  const id = useId();
  const [error, setError] = useState<string | undefined>(undefined);
  const timer = useRef<number | undefined>(undefined);

  const validate = useMemo(
    () => (candidate: string) => {
      const parsed = schema.safeParse(candidate);
      setError(parsed.success ? undefined : (parsed.error.issues[0]?.message ?? 'Invalid value'));
    },
    [schema],
  );

  return (
    <div className="flex flex-col gap-1">
      <label htmlFor={id} className="text-sm font-medium">
        {label}
      </label>
      <input
        id={id}
        type={type}
        value={value}
        autoComplete={autoComplete}
        inputMode={inputMode}
        enterKeyHint={enterKeyHint}
        aria-invalid={error !== undefined}
        aria-describedby={error === undefined ? undefined : `${id}-error`}
        onChange={event => {
          const next = event.target.value;
          onChange(next);
          if (timer.current !== undefined) window.clearTimeout(timer.current);
          timer.current = window.setTimeout(() => validate(next), debounceMs);
        }}
        className={clsx(
          'h-12 rounded-lg border bg-card px-4 text-base outline-none focus-visible:ring-2 focus-visible:ring-ring',
          error === undefined ? 'border-border' : 'border-destructive',
        )}
      />
      {error === undefined ? null : (
        <p id={`${id}-error`} role="status" className="text-sm text-destructive">
          {error}
        </p>
      )}
    </div>
  );
}
