'use client';

import { useTranslations } from 'next-intl';
import { z } from 'zod';
import { useFormDraft } from '@/adapters/hooks/useFormDraft';
import { AsyncButton } from '@/components/ui/AsyncButton';
import { Field } from '@/components/ui/Field';
import { SelectSheet } from '@/components/ui/SelectSheet';
import { AmountInput } from '@/components/ui/AmountInput';

const emailSchema = z.email('Enter a valid email address');
const nameSchema = z.string().min(1, 'This field is required');

/**
 * The settings form is the form-lifecycle showcase: drafts persist to
 * localStorage as you type (survive refresh), clear on submit, validate live
 * per field, and every async control disables with a spinner. It composes the
 * rule-defaulting components — AsyncButton, Field, SelectSheet, AmountInput.
 */
export function SettingsForm() {
  const t = useTranslations('form');
  const draft = useFormDraft('settings-form', {
    displayName: '',
    email: '',
    digestFrequency: 'weekly',
    budget: '',
  });

  return (
    <form
      className="flex flex-col gap-5"
      onSubmit={event => event.preventDefault()}
      aria-describedby={draft.restored ? 'draft-restored' : undefined}
    >
      {draft.restored ? (
        <p id="draft-restored" role="status" className="rounded-lg bg-secondary px-4 py-2 text-sm">
          {t('draftRestored')}
        </p>
      ) : null}
      <Field
        label="Display name"
        value={draft.values.displayName}
        onChange={displayName => draft.setValues({ displayName })}
        schema={nameSchema}
        autoComplete="name"
        inputMode="text"
        enterKeyHint="next"
      />
      <Field
        label="Email"
        type="email"
        value={draft.values.email}
        onChange={email => draft.setValues({ email })}
        schema={emailSchema}
        autoComplete="email"
        inputMode="email"
        enterKeyHint="next"
      />
      <SelectSheet
        label="Digest frequency"
        value={draft.values.digestFrequency}
        options={[
          { value: 'daily', label: 'Daily' },
          { value: 'weekly', label: 'Weekly' },
          { value: 'monthly', label: 'Monthly' },
        ]}
        onChange={digestFrequency => draft.setValues({ digestFrequency })}
      />
      <AmountInput
        label="Monthly budget"
        currency="USD"
        value={draft.values.budget}
        onChange={budget => draft.setValues({ budget })}
      />
      <div className="flex gap-3">
        <AsyncButton
          onAction={async () => {
            // Simulated submit; clear-on-submit is the journey the gate proves.
            await new Promise(resolve => setTimeout(resolve, 300));
            draft.clear('submit');
          }}
        >
          {t('submit')}
        </AsyncButton>
        <AsyncButton
          variant="secondary"
          onAction={async () => {
            draft.clear('reset');
          }}
        >
          {t('clear')}
        </AsyncButton>
      </div>
    </form>
  );
}
