"use client";
import { ActionForm } from "@/components/forms/action-form.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Field, Input, Textarea } from "@/components/ui/field.tsx";
import { saveSetting } from "@/lib/actions/settings.ts";

/** A whole setting as JSON, saved as a new version with a reason. The database validates the shape and the role. */
export function SettingEditor({
  name,
  value,
  readOnly,
  hint,
}: {
  name: string;
  value: string;
  readOnly: boolean;
  hint?: string;
}) {
  return (
    <ActionForm action={saveSetting}>
      <input type="hidden" name="key" value={name} />
      <Field label="Value (JSON)" hint={hint}>
        <Textarea
          name="value"
          defaultValue={value}
          readOnly={readOnly}
          spellCheck={false}
          className="min-h-80 font-mono text-xs"
        />
      </Field>
      {readOnly ? (
        <p className="text-sm text-fg-muted">Only the owner can change this setting.</p>
      ) : (
        <>
          <Field label="Reason for the change">
            <Input name="reason" required minLength={3} placeholder="Why, in a few words" />
          </Field>
          <div>
            <Button type="submit">Save as a new version</Button>
          </div>
        </>
      )}
    </ActionForm>
  );
}
