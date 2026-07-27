'use client';

import { useTranslations } from 'next-intl';
import { useUrlState } from '@/adapters/hooks/useUrlState';

/**
 * The canonical url-bound search bar recipe: typing updates local state
 * immediately and mirrors into the URL via debounced replaceState; pasting the
 * URL into a new context restores the same state (url-as-state journey).
 */
export function SearchBar() {
  const t = useTranslations('home');
  const [state, setState] = useUrlState({ q: '' });

  return (
    <search role="search" className="w-full">
      <label htmlFor="home-search" className="mb-1 block text-sm font-medium">
        {t('search')}
      </label>
      <input
        id="home-search"
        type="search"
        inputMode="search"
        enterKeyHint="search"
        autoComplete="off"
        value={state.q}
        onChange={event => setState({ q: event.target.value })}
        placeholder={t('searchPlaceholder')}
        className="h-12 w-full rounded-lg border border-border bg-card px-4 text-base outline-none focus-visible:ring-2 focus-visible:ring-ring"
      />
    </search>
  );
}
