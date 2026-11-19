"use client";

import { Field } from "@/components/ui/Field";
import { Input } from "@/components/ui/Input";
import { CONSENT } from "@/content/consent";
import { isMinor, MAX_AGE, MIN_AGE, parseAge } from "@/lib/forms/validate";
import { cn } from "@/lib/utils";

/**
 * Age, and for a student under 18 the parent/guardian consent checkbox (privacy policy of 19 Nov 2026). Used by the
 * Witty gate, the enquiry form and the application form; the server and the database check the same rule.
 */
export function AgeField({
  value,
  onChange,
  error,
  className,
}: {
  value: string;
  onChange: (age: string) => void;
  error?: string;
  className?: string;
}) {
  return (
    <Field label="Your age" hint="In years." error={error} className={className}>
      {(f) => (
        <Input
          id={f.id}
          aria-describedby={f.describedBy}
          aria-invalid={f.invalid}
          type="text"
          inputMode="numeric"
          pattern="[0-9]*"
          maxLength={2}
          autoComplete="off"
          placeholder={`${MIN_AGE}–${MAX_AGE}`}
          value={value}
          onChange={(e) => onChange(e.target.value.replace(/\D/g, "").slice(0, 2))}
        />
      )}
    </Field>
  );
}

/** Shown only once the age entered is under 18; ticking it is required to continue. */
export function GuardianConsent({
  age,
  checked,
  onChange,
  error,
  small,
}: {
  age: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
  error?: string;
  small?: boolean;
}) {
  if (!isMinor(parseAge(age))) return null;
  return (
    <>
      <label className={cn("text-muted flex items-start gap-3", small ? "text-xs leading-relaxed" : "text-sm")}>
        <input
          type="checkbox"
          className="mt-0.5 size-5 shrink-0 accent-[var(--primary)]"
          checked={checked}
          aria-invalid={!!error}
          onChange={(e) => onChange(e.target.checked)}
        />
        <span>{CONSENT.guardian.text}</span>
      </label>
      {error ? (
        <p role="alert" className="text-danger -mt-1 text-xs font-medium">
          {error}
        </p>
      ) : null}
    </>
  );
}
