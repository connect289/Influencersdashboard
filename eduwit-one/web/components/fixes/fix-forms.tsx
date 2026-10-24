"use client";
import { ActionForm } from "@/components/forms/action-form.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Field, Input, Select } from "@/components/ui/field.tsx";
import { dryRunFix, setFix, unpauseFix } from "@/lib/actions/fixes.ts";

/** The owner's switch and limits for one fix, with a reason. The database refuses a switch-on before the window ends. */
export function FixSwitchForm({
  fix,
  enabled,
  perTick,
  cooldownMin,
  canEnable,
}: {
  fix: string;
  enabled: boolean;
  perTick: number;
  cooldownMin: number;
  canEnable: boolean;
}) {
  return (
    <ActionForm action={setFix} className="sm:grid-cols-2">
      <input type="hidden" name="fix" value={fix} />
      <Field
        label="Switch"
        hint={canEnable || enabled ? undefined : "On only after the observation window, with a dry run."}
      >
        <Select name="enabled" defaultValue={enabled ? "on" : "off"}>
          <option value="off">off (dry runs only)</option>
          <option value="on" disabled={!canEnable && !enabled}>
            on
          </option>
        </Select>
      </Field>
      <Field label="Rows or calls a run (per_tick)">
        <Input name="per_tick" type="number" min={1} max={500} defaultValue={perTick} required />
      </Field>
      <Field label="Cooldown (minutes)">
        <Input name="cooldown_min" type="number" min={1} max={1440} defaultValue={cooldownMin} required />
      </Field>
      <Field label="Reason">
        <Input name="reason" required minLength={3} placeholder="Why, in a few words" />
      </Field>
      <div className="sm:col-span-2">
        <Button type="submit" variant="secondary">
          Save
        </Button>
      </div>
    </ActionForm>
  );
}

/** The owner clears a pause the breaker set (0020), with a reason that is kept in the audit. */
export function UnpauseForm({ fix }: { fix: string }) {
  return (
    <ActionForm action={unpauseFix} className="sm:grid-cols-[1fr_auto] sm:items-end">
      <input type="hidden" name="fix" value={fix} />
      <Field label="Why it may act again">
        <Input name="reason" required minLength={3} placeholder="What was put right, in a few words" />
      </Field>
      <Button type="submit" variant="secondary">
        Clear the pause
      </Button>
    </ActionForm>
  );
}

/** A dry run now on one open incident: records what the fix would do, changes nothing. */
export function DryRunForm({ fix, incident, label }: { fix: string; incident: number; label: string }) {
  return (
    <ActionForm action={dryRunFix}>
      <input type="hidden" name="fix" value={fix} />
      <input type="hidden" name="incident" value={incident} />
      <Button type="submit" variant="secondary" size="sm">
        {label}
      </Button>
    </ActionForm>
  );
}
