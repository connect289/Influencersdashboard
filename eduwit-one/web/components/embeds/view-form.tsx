"use client";
import { ActionForm } from "@/components/forms/action-form.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Field, Input, Select } from "@/components/ui/field.tsx";
import { saveView } from "@/lib/actions/ask.ts";

export function SaveViewForm({ page, params }: { page: "analytics" | "marketing"; params: string }) {
  return (
    <ActionForm action={saveView} className="sm:grid-cols-[1fr_1fr_auto] sm:items-end">
      <input type="hidden" name="page" value={page} />
      <input type="hidden" name="params" value={params} />
      <Field label="Name this view">
        <Input name="name" required maxLength={80} />
      </Field>
      <Field label="Email it" hint="Listed, with its link, in the morning brief email: daily, or on Mondays.">
        <Select name="schedule" defaultValue="">
          <option value="">No</option>
          <option value="daily">Daily</option>
          <option value="weekly">Weekly</option>
        </Select>
      </Field>
      <Button type="submit" variant="secondary">
        Save view
      </Button>
    </ActionForm>
  );
}
