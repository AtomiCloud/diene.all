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
// LOAD ORDER MATTERS. `fixtures/hook-harness` substitutes the whole `react`
// module through `mock.module`, which bun applies process-wide and which
// `mock.restore()` does NOT undo. That substitute is a synchronous hook runtime,
// not a renderer: it carries no `forwardRef` for the icon library and no
// `version` for react-dom's compatibility check, so any file rendering through
// `react-dom/server` must load BEFORE the first harness file. Bun runs files in
// alphabetical order and this name sorts ahead of `hooks`, `provider-effects`,
// and `storage-degradation`. A later rename would reintroduce the failure, so
// the guard below states the requirement rather than letting it resurface as a
// stack trace inside node_modules.
if (typeof React.forwardRef !== 'function') {
  throw new Error(
    'the react module has been substituted by fixtures/hook-harness: this file renders through react-dom/server and must load before any harness file (bun orders files alphabetically)',
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
