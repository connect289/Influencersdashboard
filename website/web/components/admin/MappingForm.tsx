"use client";

import { useActionState } from "react";
import { setMappingAction, type AdminFormState } from "@/app/admin/content-actions";

/** Maps one catalogue row to a canonical programme and specialisation(s) (spec 5.3); the finder updates at once. */
export function MappingForm({ programmes, specialisations, initialId }: { programmes: { id: string; label: string }[]; specialisations: { id: string; label: string }[]; initialId?: number }) {
  const [state, action, pending] = useActionState<AdminFormState, FormData>(setMappingAction, null);
  return (
    <form action={action} className="grid max-w-2xl gap-3 text-sm">
      <label className="grid gap-1">
        <span className="font-medium">Catalogue offering id</span>
        <input name="catalog_program_id" type="number" required defaultValue={initialId} className="border-border bg-surface h-10 rounded-[var(--radius-md)] border px-2" />
      </label>
      <label className="grid gap-1">
        <span className="font-medium">Programme</span>
        <select name="programme_id" required className="border-border bg-surface h-10 rounded-[var(--radius-md)] border px-2">
          <option value="">Choose</option>
          {programmes.map((p) => (
            <option key={p.id} value={p.id}>{p.label}</option>
          ))}
        </select>
      </label>
      <label className="grid gap-1">
        <span className="font-medium">Specialisation(s)</span>
        <select name="specialisation_ids" multiple required size={8} className="border-border bg-surface rounded-[var(--radius-md)] border p-2">
          {specialisations.map((sp) => (
            <option key={sp.id} value={sp.id}>{sp.label}</option>
          ))}
        </select>
      </label>
      <label className="grid gap-1">
        <span className="font-medium">Display name (optional)</span>
        <input name="spec_display" className="border-border bg-surface h-10 rounded-[var(--radius-md)] border px-2" />
      </label>
      <label className="grid gap-1">
        <span className="font-medium">Note</span>
        <input name="note" className="border-border bg-surface h-10 rounded-[var(--radius-md)] border px-2" />
      </label>
      {state?.error ? <p role="alert" className="text-danger">{state.error}</p> : null}
      {state?.ok ? <p role="status" className="text-success">{state.ok}</p> : null}
      <button disabled={pending} className="bg-primary text-on-primary h-10 justify-self-start rounded-full px-5 font-semibold disabled:opacity-60">
        Save mapping
      </button>
    </form>
  );
}
