"use client";
import { ActionForm } from "@/components/forms/action-form.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Field, Input, Select } from "@/components/ui/field.tsx";
import { mute, unmute } from "@/lib/actions/incidents.ts";
import { acceptBaseline, acknowledgePrivilege, putUser, revokeDevices } from "@/lib/actions/settings.ts";

export function MuteForm({ apps }: { apps: Array<[string, string]> }) {
  return (
    <ActionForm action={mute} className="sm:grid-cols-2">
      <input type="hidden" name="back" value="/settings/maintenance" />
      <Field label="Mute">
        <Select name="target_type" defaultValue="app">
          <option value="app">An app (maintenance window)</option>
          <option value="check">A check</option>
        </Select>
      </Field>
      <Field label="App key or check id" hint={`Apps: ${apps.map(([k]) => k).join(", ")}`}>
        <Input name="target" required list="mute-targets" />
      </Field>
      <datalist id="mute-targets">
        {apps.map(([k, name]) => (
          <option key={k} value={k}>
            {name}
          </option>
        ))}
      </datalist>
      <Field label="Minutes">
        <Input name="minutes" type="number" min={1} max={10080} defaultValue={60} required />
      </Field>
      <Field label="Reason">
        <Input name="reason" required minLength={3} />
      </Field>
      <div className="sm:col-span-2">
        <Button type="submit">Start</Button>
      </div>
    </ActionForm>
  );
}

export function UnmuteButton({ id }: { id: number }) {
  return (
    <ActionForm action={unmute}>
      <input type="hidden" name="id" value={id} />
      <Button type="submit" variant="ghost" size="sm">
        End now
      </Button>
    </ActionForm>
  );
}

export function UserForm({ email, role, active }: { email?: string; role?: string; active?: boolean }) {
  return (
    <ActionForm action={putUser} className="sm:grid-cols-[2fr_1fr_auto_auto] sm:items-end">
      <Field label="Email">
        <Input
          name="email"
          type="email"
          defaultValue={email}
          readOnly={Boolean(email)}
          required
          placeholder="name@eduwit.in"
        />
      </Field>
      <Field label="Role">
        <Select name="role" defaultValue={role ?? "engineer"}>
          <option value="engineer">Engineer</option>
          <option value="owner">Owner</option>
        </Select>
      </Field>
      <label className="flex min-h-10 items-center gap-2 text-sm">
        <input type="checkbox" name="active" defaultChecked={active ?? true} className="size-4" /> Active
      </label>
      <Button type="submit" size="sm">
        {email ? "Save" : "Add"}
      </Button>
    </ActionForm>
  );
}

export function RevokeDevicesButton({ userId }: { userId: string }) {
  return (
    <ActionForm action={revokeDevices}>
      <input type="hidden" name="user_id" value={userId} />
      <Button type="submit" variant="ghost" size="sm">
        Sign out everywhere
      </Button>
    </ActionForm>
  );
}

export function AckPrivilegeButton({ fn }: { fn: string }) {
  return (
    <ActionForm action={acknowledgePrivilege}>
      <input type="hidden" name="fn" value={fn} />
      <Button type="submit" variant="secondary" size="sm">
        Acknowledge
      </Button>
    </ActionForm>
  );
}

export function AcceptBaselineButton({ name }: { name: string }) {
  return (
    <ActionForm action={acceptBaseline}>
      <input type="hidden" name="key" value={name} />
      <Button type="submit" variant="secondary" size="sm">
        Accept the current state
      </Button>
    </ActionForm>
  );
}
