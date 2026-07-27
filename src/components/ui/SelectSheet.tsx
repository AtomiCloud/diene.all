'use client';

import { clsx } from 'clsx';
import { ChevronDown, X } from 'lucide-react';
import { useEffect, useId, useRef, useState } from 'react';

export interface SelectOption {
  readonly value: string;
  readonly label: string;
}

/**
 * Select-as-bottom-sheet-on-mobile: never a native dropdown that navigates
 * away. Renders a trigger button; the option list opens as a modal bottom
 * sheet (mobile) / centered dialog (wider viewports) with focus handling and
 * backdrop dismissal that PRESERVES state.
 */
export function SelectSheet({
  label,
  value,
  options,
  onChange,
  className,
}: {
  readonly label: string;
  readonly value: string;
  readonly options: readonly SelectOption[];
  readonly onChange: (value: string) => void;
  readonly className?: string;
}) {
  const id = useId();
  const [open, setOpen] = useState(false);
  const dialogRef = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    const dialog = dialogRef.current;
    if (dialog === null) return;
    if (open && !dialog.open) dialog.showModal();
    if (!open && dialog.open) dialog.close();
  }, [open]);

  const selected = options.find(option => option.value === value);

  return (
    <div className={clsx('flex flex-col gap-1', className)}>
      <span id={`${id}-label`} className="text-sm font-medium">
        {label}
      </span>
      <button
        type="button"
        aria-haspopup="dialog"
        aria-labelledby={`${id}-label`}
        onClick={() => setOpen(true)}
        className="flex h-12 items-center justify-between rounded-lg border border-border bg-card px-4 outline-none focus-visible:ring-2 focus-visible:ring-ring"
      >
        <span>{selected?.label ?? value}</span>
        <ChevronDown aria-hidden size={18} />
      </button>
      <dialog
        ref={dialogRef}
        aria-labelledby={`${id}-label`}
        onClose={() => setOpen(false)}
        onClick={event => {
          // Backdrop tap: accidental dismissal, state preserved.
          if (event.target === dialogRef.current) setOpen(false);
        }}
        className="m-0 mt-auto w-full max-w-full rounded-t-2xl border border-border bg-card p-0 backdrop:bg-black/40 sm:m-auto sm:max-w-md sm:rounded-2xl"
      >
        <div className="flex items-center justify-between border-b border-border p-4">
          <span className="font-medium">{label}</span>
          <button
            type="button"
            aria-label="Close"
            onClick={() => setOpen(false)}
            className="flex h-11 w-11 items-center justify-center rounded-lg outline-none focus-visible:ring-2 focus-visible:ring-ring"
          >
            <X aria-hidden size={18} />
          </button>
        </div>
        <ul className="max-h-80 overflow-auto p-2">
          {options.map(option => (
            <li key={option.value}>
              <button
                type="button"
                aria-pressed={option.value === value}
                onClick={() => {
                  onChange(option.value);
                  setOpen(false);
                }}
                className={clsx(
                  'flex h-12 w-full items-center rounded-lg px-4 text-left outline-none focus-visible:ring-2 focus-visible:ring-ring',
                  option.value === value ? 'bg-secondary font-medium' : 'hover:bg-muted',
                )}
              >
                {option.label}
              </button>
            </li>
          ))}
        </ul>
      </dialog>
    </div>
  );
}
