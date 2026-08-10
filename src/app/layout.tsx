import type { ReactNode } from 'react';

// The root layout defers everything to the [locale] segment; next-intl's
// middleware guarantees every request lands there.
export default function RootLayout({ children }: { readonly children: ReactNode }) {
  return children;
}
