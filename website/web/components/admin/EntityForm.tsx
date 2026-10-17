"use client";

import { useActionState } from "react";
import { saveEntityAction, type AdminFormState } from "@/app/admin/content-actions";
import type { EntityConfig, Field } from "@/lib/admin/entities";

/** Generic edit form for one content row; server-validated, audited, revalidates the public pages on save. */
function valueFor(f: Field, v: unknown): string {
  if (v === null || v === undefined) return "";
  if (f.type === "json") return JSON.stringify(v, null, 2);
  if (f.type === "tags") return Array.isArray(v) ? v.join(", ") : String(v);
  if (f.type === "datetime") return String(v).slice(0, 16);
  return String(v);
}

export function EntityForm({ cfg, row, keyJson, canEdit, saved }: { cfg: EntityConfig; row: Record<string, unknown> | null; keyJson: string | null; canEdit: boolean; saved?: boolean }) {
  const [state, action, pending] = useActionState<AdminFormState, FormData>(saveEntityAction, saved ? { ok: "Saved and published." } : null);
  const isNew = !keyJson;
  const typed = state?.values;
  return (
    // remount with the submitted values after a rejected save (React resets forms after an action)
    <form key={typed ? JSON.stringify(typed) : "initial"} action={action} className="grid max-w-3xl gap-4">
      <input type="hidden" name="__entity" value={cfg.entity} />
      {keyJson ? <input type="hidden" name="__key" value={keyJson} /> : null}
      {cfg.fields.map((f) => {
        const id = `f-${f.name}`;
        const err = state?.fieldErrors?.[f.name];
        const locked = !canEdit || (!isNew && (f.key || f.readOnly)) || (isNew && f.readOnly);
        const common = { id, name: f.name, disabled: locked, "aria-invalid": err ? true : undefined, "aria-describedby": f.help || err ? `${id}-hint` : undefined };
        const v = typed ? (typed[f.name] ?? "") : valueFor(f, row?.[f.name]);
        const checked = typed ? typed[f.name] === "on" : row?.[f.name] === true;
        return (
          <div key={f.name} className="grid gap-1">
            {f.type === "bool" ? (
              <label htmlFor={id} className="flex items-center gap-2 text-sm font-medium">
                <input type="checkbox" {...common} defaultChecked={checked} className="size-4" />
                {f.label}
              </label>
            ) : (
              <>
                <label htmlFor={id} className="text-sm font-medium">
                  {f.label}
                  {f.required ? <span className="text-danger"> *</span> : null}
                </label>
                {f.type === "textarea" || f.type === "json" ? (
                  <textarea {...common} defaultValue={v} rows={f.type === "json" ? 8 : 4} className={`border-border bg-surface rounded-[var(--radius-md)] border p-2 text-sm ${f.type === "json" ? "font-mono" : ""}`} />
                ) : f.type === "select" ? (
                  <select {...common} defaultValue={v} className="border-border bg-surface h-10 rounded-[var(--radius-md)] border px-2 text-sm">
                    <option value="">—</option>
                    {f.options?.map((o) => (
                      <option key={o} value={o}>{o}</option>
                    ))}
                  </select>
                ) : (
                  <input {...common} type={f.type === "number" ? "number" : f.type === "datetime" ? "datetime-local" : f.type === "url" ? "text" : "text"} step={f.type === "number" ? "any" : undefined} defaultValue={v} className="border-border bg-surface h-10 rounded-[var(--radius-md)] border px-2 text-sm" />
                )}
              </>
            )}
            {locked && !isNew && (f.key || f.readOnly) ? <input type="hidden" name={f.name} value={v} /> : null}
            {f.help || err ? (
              <p id={`${id}-hint`} className={err ? "text-danger text-xs" : "text-subtle text-xs"}>
                {err ?? f.help}
              </p>
            ) : null}
          </div>
        );
      })}
      {state?.error ? <p role="alert" className="text-danger text-sm">{state.error}</p> : null}
      {state?.ok ? <p role="status" className="text-success text-sm">{state.ok}</p> : null}
      {canEdit ? (
        <div>
          <button type="submit" disabled={pending} className="bg-primary text-on-primary h-10 rounded-full px-5 text-sm font-semibold disabled:opacity-60">
            {pending ? "Saving…" : "Save and publish"}
          </button>
        </div>
      ) : (
        <p className="text-muted text-sm">Read only for your role.</p>
      )}
    </form>
  );
}
