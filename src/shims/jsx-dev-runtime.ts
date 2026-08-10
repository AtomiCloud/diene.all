// TEMPORARY SHIM — remove when @atomicloud/diene.frontend-utils@1.0.1 ships.
//
// frontend-utils@1.0.0 published its React bindings compiled against
// react/jsx-dev-runtime (jsxDEV), which does not exist in production React.
// This shim delegates jsxDEV to the production jsx-runtime so the REAL lib
// imports keep working unmodified (reported upstream via the lead inbox on
// 2026-07-25; no lib code is patched or vendored).
import { Fragment, jsx, jsxs } from 'react/jsx-runtime';

type JsxProps = Record<string, unknown> & { children?: unknown };

export { Fragment };

export function jsxDEV(type: unknown, props: JsxProps, key?: unknown): unknown {
  const factory = Array.isArray(props?.children) ? jsxs : jsx;
  return (factory as (type: unknown, props: JsxProps, key?: unknown) => unknown)(type, props, key);
}
