import * as a11yExports from './lib/a11y/index.js';
import * as contentExports from './lib/content/index.js';
import * as discoveryExports from './lib/discovery/index.js';
import * as landscapeExports from './lib/landscape/index.js';
import * as loaderExports from './lib/loader/index.js';
import * as moduleExports from './lib/module/index.js';
import * as persistenceExports from './lib/persistence/index.js';
import * as themeExports from './lib/theme/index.js';
import * as toastExports from './lib/toast/index.js';
import * as urlstateExports from './lib/urlstate/index.js';

/**
 * Root imports expose runtime namespaces for discovery. Consumers should use
 * the focused subpath entries for types and tree-shaking.
 */
export const a11y = Object.freeze({ ...a11yExports });
export const content = Object.freeze({ ...contentExports });
export const discovery = Object.freeze({ ...discoveryExports });
export const landscape = Object.freeze({ ...landscapeExports });
export const loader = Object.freeze({ ...loaderExports });
export const module = Object.freeze({ ...moduleExports });
export const persistence = Object.freeze({ ...persistenceExports });
export const theme = Object.freeze({ ...themeExports });
export const toast = Object.freeze({ ...toastExports });
export const urlstate = Object.freeze({ ...urlstateExports });
