"use client";
import { ActionForm } from "@/components/forms/action-form.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Field, Input } from "@/components/ui/field.tsx";
import { saveSecret, validateItem } from "@/lib/actions/setup.ts";

export function ValidateButton({ id }: { id: string }) {
  return (
    <ActionForm action={validateItem}>
      <input type="hidden" name="id" value={id} />
      <Button type="submit" variant="secondary" size="sm">
        Validate
      </Button>
    </ActionForm>
  );
}

/** A secret goes to Vault; the field is a password field and the value never comes back to the page. */
export function SecretForm({ name }: { name: string }) {
  return (
    <ActionForm action={saveSecret} className="sm:grid-cols-[1fr_auto] sm:items-end">
      <input type="hidden" name="name" value={name} />
      <Field label={name}>
        <Input name="value" type="password" autoComplete="off" required minLength={8} placeholder="paste the value" />
      </Field>
      <Button type="submit" size="sm">
        Save to Vault
      </Button>
    </ActionForm>
  );
}
