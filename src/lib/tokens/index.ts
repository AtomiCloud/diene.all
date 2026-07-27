import type { CssVariableThemeMap } from '@atomicloud/diene.frontend-utils/theme';

/**
 * User-space design tokens (frontend-ux doctrine Layer 3). The identity
 * scaffold step (docs/domain/identity.md) REQUIRES replacing these values with
 * the product's palette — an app cannot ship default-grey, so the sample bakes
 * a deliberately opinionated non-grey identity that the scaffold prompts you
 * to overwrite.
 */
export const themeCssVariables: CssVariableThemeMap = {
  light: {
    '--background': 'oklch(0.985 0.008 84)',
    '--foreground': 'oklch(0.24 0.03 260)',
    '--card': 'oklch(1 0 0)',
    '--card-foreground': 'oklch(0.24 0.03 260)',
    '--primary': 'oklch(0.55 0.16 255)',
    '--primary-foreground': 'oklch(0.985 0.008 84)',
    '--secondary': 'oklch(0.92 0.04 84)',
    '--secondary-foreground': 'oklch(0.3 0.05 260)',
    '--muted': 'oklch(0.95 0.015 84)',
    '--muted-foreground': 'oklch(0.5 0.02 260)',
    '--accent': 'oklch(0.75 0.14 84)',
    '--accent-foreground': 'oklch(0.24 0.03 260)',
    '--destructive': 'oklch(0.55 0.2 25)',
    '--destructive-foreground': 'oklch(0.985 0.008 84)',
    '--border': 'oklch(0.9 0.015 84)',
    '--ring': 'oklch(0.55 0.16 255)',
  },
  dark: {
    '--background': 'oklch(0.17 0.02 260)',
    '--foreground': 'oklch(0.95 0.01 84)',
    '--card': 'oklch(0.22 0.025 260)',
    '--card-foreground': 'oklch(0.95 0.01 84)',
    '--primary': 'oklch(0.7 0.14 255)',
    '--primary-foreground': 'oklch(0.17 0.02 260)',
    '--secondary': 'oklch(0.3 0.04 260)',
    '--secondary-foreground': 'oklch(0.95 0.01 84)',
    '--muted': 'oklch(0.27 0.03 260)',
    '--muted-foreground': 'oklch(0.7 0.02 84)',
    '--accent': 'oklch(0.75 0.14 84)',
    '--accent-foreground': 'oklch(0.17 0.02 260)',
    '--destructive': 'oklch(0.65 0.2 25)',
    '--destructive-foreground': 'oklch(0.17 0.02 260)',
    '--border': 'oklch(0.3 0.03 260)',
    '--ring': 'oklch(0.7 0.14 255)',
  },
};
