import type { ReactNode } from 'react';

/**
 * Safe-area-aware layout shell for edge-anchored UI: pads by the
 * `--safe-area-*` variables (env(safe-area-inset-*), defined in globals.css)
 * so notches and home indicators never cover content.
 */
export function SafeAreaShell({ children }: { readonly children: ReactNode }) {
  return (
    <div
      className="min-h-dvh"
      style={{
        paddingTop: 'var(--safe-area-top)',
        paddingRight: 'var(--safe-area-right)',
        paddingBottom: 'var(--safe-area-bottom)',
        paddingLeft: 'var(--safe-area-left)',
      }}
    >
      {children}
    </div>
  );
}
