'use client';

import { useTheme } from '@atomicloud/diene.frontend-utils/theme/react';
import { useTranslations } from 'next-intl';
import { Moon, Sun } from 'lucide-react';

/** Runtime theme switcher riding the CSS-variable mechanism (persists). */
export function ThemeToggle() {
  const t = useTranslations('theme');
  const { isDark, setTheme } = useTheme();

  return (
    <button
      type="button"
      aria-label={t('toggle')}
      onClick={() => setTheme(isDark ? 'light' : 'dark')}
      className="flex h-11 w-11 items-center justify-center rounded-lg border border-border bg-card text-foreground outline-none focus-visible:ring-2 focus-visible:ring-ring"
    >
      {isDark ? <Sun aria-hidden size={20} /> : <Moon aria-hidden size={20} />}
    </button>
  );
}
