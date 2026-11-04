"use client";
import { ActionForm } from "@/components/forms/action-form.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Field, Input, Textarea } from "@/components/ui/field.tsx";
import { decide } from "@/lib/actions/proposals.ts";

/** Approve (optionally with edited arguments), reject with a note, or snooze. Phone-friendly: one column, big targets. */
export function DecideForm({ id, change, canApprove }: { id: number; change: string; canApprove: boolean }) {
  return (
    <div className="grid gap-4">
      <ActionForm action={decide}>
        <input type="hidden" name="id" value={id} />
        <input type="hidden" name="decision" value="approve" />
        <Field label="The change to approve" hint="Edit the arguments if needed; both versions are kept in the audit.">
          <Textarea name="change" defaultValue={change} className="min-h-32 font-mono text-xs" />
        </Field>
        <Field label="Note (optional)">
          <Input name="note" />
        </Field>
        <Button type="submit" disabled={!canApprove}>
          Approve
        </Button>
        {!canApprove ? <p className="text-xs text-fg-muted">This one is the owner&apos;s to approve.</p> : null}
      </ActionForm>
      <ActionForm action={decide}>
        <input type="hidden" name="id" value={id} />
        <input type="hidden" name="decision" value="reject" />
        <Field label="Why reject">
          <Input name="note" required minLength={3} />
        </Field>
        <Button type="submit" variant="danger">
          Reject
        </Button>
      </ActionForm>
      <ActionForm action={decide}>
        <input type="hidden" name="id" value={id} />
        <input type="hidden" name="decision" value="snooze" />
        <Field label="Snooze for (days)">
          <Input name="snooze_days" type="number" min={1} max={30} defaultValue={7} required />
        </Field>
        <Button type="submit" variant="secondary">
          Snooze
        </Button>
      </ActionForm>
    </div>
  );
}
