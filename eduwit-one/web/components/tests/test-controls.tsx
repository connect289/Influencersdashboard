"use client";
import { ActionForm } from "@/components/forms/action-form.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Field, Input } from "@/components/ui/field.tsx";
import { runTest, updateTest } from "@/lib/actions/settings.ts";

export function TestControls({ id, enabled, schedule }: { id: string; enabled: boolean; schedule: string }) {
  return (
    <div className="grid gap-3 sm:grid-cols-2">
      <ActionForm action={runTest}>
        <input type="hidden" name="id" value={id} />
        <Button type="submit" variant="secondary" disabled={!enabled}>
          Run now
        </Button>
      </ActionForm>
      <details>
        <summary className="cursor-pointer text-sm">Switch or schedule</summary>
        <ActionForm action={updateTest} className="mt-2">
          <input type="hidden" name="id" value={id} />
          <input type="hidden" name="enabled" value={enabled ? "off" : "on"} />
          <Field label="Schedule (cron, UTC)">
            <Input name="schedule" defaultValue={schedule} />
          </Field>
          <Field label="Reason">
            <Input name="reason" required minLength={3} />
          </Field>
          <Button type="submit" variant="secondary">
            {enabled ? "Switch off and save" : "Switch on and save"}
          </Button>
        </ActionForm>
      </details>
    </div>
  );
}
