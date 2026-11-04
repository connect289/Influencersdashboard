"use client";
import { ActionForm } from "@/components/forms/action-form.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Field, Input, Select } from "@/components/ui/field.tsx";
import { updateCheck } from "@/lib/actions/settings.ts";

type Props = {
  id: string;
  enabled: boolean;
  severity: string;
  cadence_s: number;
  open_after: number;
  resolve_after: number;
  blocked: boolean;
};

export function CheckForm(c: Props) {
  return (
    <ActionForm action={updateCheck} className="sm:grid-cols-3">
      <input type="hidden" name="id" value={c.id} />
      <Field label="Switch">
        <Select name="enabled" defaultValue={c.enabled ? "on" : "off"} disabled={c.blocked && !c.enabled}>
          <option value="on">On</option>
          <option value="off">Off</option>
        </Select>
      </Field>
      <Field label="Severity">
        <Select name="severity" defaultValue={c.severity}>
          <option value="P1">P1</option>
          <option value="P2">P2</option>
          <option value="P3">P3</option>
        </Select>
      </Field>
      <Field label="Every (seconds)">
        <Input name="cadence_s" type="number" min={60} max={604800} defaultValue={c.cadence_s} />
      </Field>
      <Field label="Open after N failures">
        <Input name="open_after" type="number" min={1} max={60} defaultValue={c.open_after} />
      </Field>
      <Field label="Resolve after N passes">
        <Input name="resolve_after" type="number" min={1} max={60} defaultValue={c.resolve_after} />
      </Field>
      <Field label="Reason">
        <Input name="reason" required minLength={3} />
      </Field>
      <div className="sm:col-span-3">
        <Button type="submit" size="sm">
          Save
        </Button>
      </div>
    </ActionForm>
  );
}
