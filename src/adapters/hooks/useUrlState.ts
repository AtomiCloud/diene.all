'use client';

import {
  createUrlStateController,
  readUrlState,
  type UrlStateController,
} from '@atomicloud/diene.frontend-utils/urlstate';
import { useEffect, useMemo, useRef, useState } from 'react';

/**
 * url-as-state hook — the template's binding over the lib's controller core
 * (evolved from argon's urlstate). Server reads on load (`searchParams` →
 * initial state via readUrlState in the page); client updates on interaction
 * through a debounced replaceState. Deep-linkable and back/forward-correct.
 *
 * `defaults` is captured on first render (call-site literal by contract), so
 * the controller survives re-renders without resubscribing.
 */
export function useUrlState<T extends Record<string, string>>(defaults: T): [T, (patch: Partial<T>) => void] {
  const defaultsRef = useRef(defaults);

  const controller = useMemo<UrlStateController<T>>(
    () =>
      createUrlStateController({
        defaults: defaultsRef.current,
        initial: readUrlState(window.location.search, defaultsRef.current),
        history: {
          replaceState: search => {
            const url = `${window.location.pathname}${search}${window.location.hash}`;
            window.history.replaceState(window.history.state, '', url);
          },
        },
        scheduler: {
          setTimer: (fn, ms) => window.setTimeout(fn, ms),
          clearTimer: handle => window.clearTimeout(handle as number),
        },
      }),
    [],
  );

  const [state, setState] = useState<T>(controller.getState());

  useEffect(() => {
    const unsubscribe = controller.subscribe(setState);
    const onPopState = () => {
      // Back/forward restores state from the URL the browser navigated to.
      controller.setState(readUrlState(window.location.search, defaultsRef.current));
      controller.flush();
    };
    window.addEventListener('popstate', onPopState);
    return () => {
      window.removeEventListener('popstate', onPopState);
      unsubscribe();
      controller.destroy();
    };
  }, [controller]);

  return [state, controller.setState];
}
