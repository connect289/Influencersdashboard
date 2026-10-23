"use client";
import { ActionForm } from "@/components/forms/action-form.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Field, Input, Select, Textarea } from "@/components/ui/field.tsx";
import { ask, pin, regenerateBrief } from "@/lib/actions/ask.ts";

export function RegenerateForm({ date }: { date: string }) {
  return (
    <ActionForm action={regenerateBrief} className="sm:grid-cols-[1fr_1fr_auto] sm:items-end">
      <Field label="Day">
        <Input type="date" name="for_date" defaultValue={date} required />
      </Field>
      <Field label="Tier">
        <Select name="tier" defaultValue="regular">
          <option value="quick">Quick</option>
          <option value="regular">Regular</option>
          <option value="deep">Deep</option>
        </Select>
      </Field>
      <Button type="submit" variant="secondary">
        Re-generate
      </Button>
    </ActionForm>
  );
}

export function AskForm() {
  return (
    <ActionForm action={ask}>
      <Field
        label="Your question"
        hint="About the five apps' data and Eduwit One's own records. Answers never include a student's name, phone or email."
      >
        <Textarea
          name="question"
          required
          minLength={3}
          maxLength={2000}
          placeholder="How many Witty leads were allocated yesterday, by partner?"
        />
      </Field>
      <div>
        <Button type="submit">Ask</Button>
      </div>
    </ActionForm>
  );
}

export function PinButton({ id }: { id: number }) {
  return (
    <ActionForm action={pin}>
      <input type="hidden" name="id" value={id} />
      <Button type="submit" variant="ghost" size="sm">
        Pin to the brief
      </Button>
    </ActionForm>
  );
}
