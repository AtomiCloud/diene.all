'use client';

import { clsx } from 'clsx';
import { Loader2 } from 'lucide-react';
import type { ReactNode } from 'react';
import { useAsyncAction } from '@/adapters/hooks/useAsyncAction';

/**
 * Rule-defaulting async button: spinner inside-left, 44-48px touch target,
 * visible focus ring, disabled while the action is in flight (no dead clicks,
 * no double submit). The pending state is the DEFAULT — a consumer cannot
 * forget it.
 */
export function AsyncButton({
  onAction,
  children,
  variant = 'primary',
  className,
}: {
  readonly onAction: () => Promise<void>;
  readonly children: ReactNode;
  readonly variant?: 'primary' | 'secondary' | 'destructive';
  readonly className?: string;
}) {
  const { pending, run } = useAsyncAction(onAction);

  return (
    <button
      type="button"
      onClick={run}
      disabled={pending}
      aria-busy={pending}
      className={clsx(
        'inline-flex h-12 min-w-12 items-center justify-center gap-2 rounded-lg px-6 font-medium outline-none transition-opacity focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-60',
        variant === 'primary' && 'bg-primary text-primary-foreground',
        variant === 'secondary' && 'bg-secondary text-secondary-foreground',
        variant === 'destructive' && 'bg-destructive text-destructive-foreground',
        className,
      )}
    >
      {pending ? <Loader2 aria-hidden className="size-5 animate-spin" /> : null}
      {children}
    </button>
  );
}
