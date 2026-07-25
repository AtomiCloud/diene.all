'use client';

import { clsx } from 'clsx';
import { Delete } from 'lucide-react';
import { useId } from 'react';

const KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', '⌫'] as const;

/**
 * Keypad AmountInput: a custom keypad, never the default keyboard — the value
 * surface is a read-only display and every mutation goes through the keypad,
 * so mobile users never fight an OS numeric layout.
 */
export function AmountInput({
  label,
  value,
  onChange,
  currency,
  className,
}: {
  readonly label: string;
  readonly value: string;
  readonly onChange: (value: string) => void;
  readonly currency: string;
  readonly className?: string;
}) {
  const id = useId();

  const press = (key: (typeof KEYS)[number]) => {
    if (key === '⌫') {
      onChange(value.slice(0, -1));
      return;
    }
    if (key === '.' && (value.includes('.') || value === '')) return;
    const next = value + key;
    if (/^\d*(\.\d{0,2})?$/.test(next)) onChange(next);
  };

  return (
    <div className={clsx('flex flex-col gap-2', className)}>
      <label htmlFor={id} className="text-sm font-medium">
        {label}
      </label>
      <output
        id={id}
        aria-live="polite"
        className="flex h-14 items-center justify-end rounded-lg border border-border bg-card px-4 text-2xl font-semibold tabular-nums"
      >
        {currency} {value === '' ? '0' : value}
      </output>
      <div role="group" aria-label={label} className="grid grid-cols-3 gap-2">
        {KEYS.map(key => (
          <button
            key={key}
            type="button"
            aria-label={key === '⌫' ? 'Delete' : key}
            onClick={() => press(key)}
            className="flex h-12 items-center justify-center rounded-lg border border-border bg-card text-lg font-medium outline-none focus-visible:ring-2 focus-visible:ring-ring active:bg-muted"
          >
            {key === '⌫' ? <Delete aria-hidden size={20} /> : key}
          </button>
        ))}
      </div>
    </div>
  );
}
