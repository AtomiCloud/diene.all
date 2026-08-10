import { clsx } from 'clsx';

/**
 * Skeleton that reserves final dimensions (CLS-safe): callers size it to the
 * content it stands in for, so layout never shifts when content arrives.
 */
export function Skeleton({ className }: { readonly className?: string }) {
  return <div aria-hidden className={clsx('animate-pulse rounded-md bg-muted', className)} />;
}
