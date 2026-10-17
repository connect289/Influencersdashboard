"use client";

import { useActionState } from "react";
import { saveSettingAction, type AdminFormState } from "@/app/admin/content-actions";

/** One setting or feature flag, saved immediately (audited; the public site picks it up at once). */
export function SettingForm({ name, label, help, kind, value, disabled }: { name: string; label: string; help?: string; kind: "bool" | "text" | "number" | "json"; value: unknown; disabled?: boolean }) {
  const [state, action, pending] = useActionState<AdminFormState, FormData>(saveSettingAction, null);
  const id = `s-${name}`;
  return (
    <form action={action} className="border-border grid gap-2 border-b py-3 last:border-0">
      <input type="hidden" name="key" value={name} />
      <input type="hidden" name="kind" value={kind} />
      <div className="flex flex-wrap items-center justify-between gap-3">
        <label htmlFor={id} className="text-sm font-medium">
          {label}
        </label>
        <div className="flex items-center gap-2">
          {kind === "bool" ? (
            <input id={id} name="value" type="checkbox" defaultChecked={value === true} disabled={disabled} className="size-5" />
          ) : kind === "json" ? null : (
            <input id={id} name="value" type={kind === "number" ? "number" : "text"} defaultValue={value === null || value === undefined ? "" : String(value)} disabled={disabled} className="border-border bg-surface h-9 w-56 rounded-[var(--radius-md)] border px-2 text-sm" />
          )}
          <button type="submit" disabled={pending || disabled} className="border-border h-9 rounded-full border px-3 text-sm disabled:opacity-50">
            Save
          </button>
        </div>
      </div>
      {kind === "json" ? (
        <textarea id={id} name="value" rows={3} defaultValue={value === null || value === undefined ? "" : JSON.stringify(value, null, 2)} disabled={disabled} className="border-border bg-surface rounded-[var(--radius-md)] border p-2 font-mono text-xs" />
      ) : null}
      {help ? <p className="text-subtle text-xs">{help}</p> : null}
      {state?.error ? <p role="alert" className="text-danger text-xs">{state.error}</p> : null}
      {state?.ok ? <p role="status" className="text-success text-xs">{state.ok}</p> : null}
    </form>
  );
}
