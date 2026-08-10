import { describe, it } from 'bun:test';
import should from 'should';
import * as React from 'react';
import type { ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { NextIntlClientProvider } from 'next-intl';
import { installBrowser, fakeStorage } from './fixtures/browser';
import { intConfig } from './fixtures/config';
import messages from '../../messages/en.json';
import { PickerFlow } from '../../src/components/picker/PickerFlow';
import { clientSafeConfig } from '../../src/adapters/server-config';
import { ClientConfigProvider } from '../../src/adapters/atomi/ClientConfigProvider';

// Integration: the picker flow's ORDERING contract (app-handoff legal gate).
// A legal/consent step must be the first thing a signing-up user sees — before
// Doc B is fetched, before any landscape is named, before anything is pinged.
// SSR is the right tier for it: the ordering is a render-time property, and the
// first paint is exactly what the requirement is about. Interactive progression
// through the flow is the e2e tier's concern.
//
// `fixtures/hook-harness` substitutes the whole `react` module through
// `mock.module`; every harness file restores the real modules in `afterAll`
// via `restoreReact` (CI proved file order is filesystem-dependent, so load
// order cannot be relied on). This guard fails legibly if a harness file ever
// skips its restore and leaves the hook stub installed.
if (typeof React.forwardRef !== 'function') {
  throw new Error(
    'the react module is still the fixtures/hook-harness stub: a harness file did not call restoreReact() in afterAll — this file renders through react-dom/server and needs the real React',
  );
}

const render = async (child: ReactNode): Promise<string> => {
  const config = clientSafeConfig(await intConfig('base'), 'lapras');
  return renderToStaticMarkup(
    // A client component rendered through react-dom/server makes use-intl warn
    // that it cannot detect its environment. The warning is about the harness,
    // not the component, so it is swallowed rather than left to clutter the run.
    <NextIntlClientProvider locale="en" messages={messages} onError={() => undefined}>
      <ClientConfigProvider config={config}>{child}</ClientConfigProvider>
    </NextIntlClientProvider>,
  );
};

describe('PickerFlow first paint', () => {
  it('should present the legal step before anything else', async () => {
    // Arrange
    const restore = installBrowser(fakeStorage()).restore;

    // Act
    const html = await render(<PickerFlow onConfirmed={async () => undefined} />);
    restore();

    // Assert — the legal section is what renders, carrying its accept control.
    should(html).match(/aria-label="legal"/);
    should(html).containEql(messages.picker.legalTitle);
    should(html).containEql(messages.picker.legalAccept);
  });

  it('should name no landscape and offer no choice before consent', async () => {
    // Arrange — consent that arrives AFTER the list is a consent the user has
    // already been influenced by, so the list must not exist yet at all.
    const restore = installBrowser(fakeStorage()).restore;

    // Act
    const html = await render(<PickerFlow onConfirmed={async () => undefined} />);
    restore();

    // Assert
    should(html).not.match(/aria-label="picker"/);
    should(html).not.match(/aria-label="measuring"/);
    should(html).not.match(/name="home-landscape"/);
    should(html).not.containEql(messages.picker.confirm);
  });
});
