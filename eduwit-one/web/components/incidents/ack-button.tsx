"use client";
import { ActionForm } from "@/components/forms/action-form.tsx";
import { Button } from "@/components/ui/button.tsx";
import { acknowledge } from "@/lib/actions/incidents.ts";

/** Acknowledge from a list (the Overview's "what needs attention"), without opening the incident. */
export function AckButton({ id }: { id: number | string }) {
  return (
    <ActionForm action={acknowledge}>
      <input type="hidden" name="id" value={String(id)} />
      <Button type="submit" variant="secondary" size="sm">
        Acknowledge
      </Button>
    </ActionForm>
  );
}
