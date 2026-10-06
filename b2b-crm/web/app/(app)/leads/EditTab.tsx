"use client";
import { useEffect, useMemo, useState } from "react";
import { History, LoaderCircle, TriangleAlert } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { EmptyState } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { useFormAction } from "@/components/ui/useFormAction";
import { formatDateTime, relativeTime } from "@/lib/format";
import { CLASSIFICATIONS, EDIT_FIELDS, EDIT_GROUPS, FIELD_LABEL, type EditField, type EditHistory } from "@/lib/lead-edit";
import { humanize } from "@/lib/leads";
import { editLead, type EditState } from "./actions";

const field = "w-full rounded-lg border border-border bg-surface px-3 text-[13px] text-fg focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 aria-[invalid=true]:border-danger";

/** The lead's correctable fields and their history. Every save needs a reason and is kept field by field. */
export function EditTab({ id, lead, history, deleted }: { id: number; lead: Record<string, unknown>; history: EditHistory | null; deleted: boolean }) {
  const original = useMemo(() => Object.fromEntries(EDIT_FIELDS.map((f) => {
    const v = lead[f];
    return [f, v === null || v === undefined || v === "" ? null : String(v)];
  })) as Record<EditField, string | null>, [lead]);
  const [state, onSubmit, pending] = useFormAction<EditState>(editLead.bind(null, id), undefined);
  const [values, setValues] = useState<Record<string, string>>(() => Object.fromEntries(EDIT_FIELDS.map((f) => [f, original[f] ?? ""])));
  const dirty = EDIT_FIELDS.filter((f) => (values[f] ?? "") !== (original[f] ?? ""));
  const e = state?.errors ?? {};

  useEffect(() => {
    if (state?.ok) toast.success(state.changed ? `Saved ${state.changed} ${state.changed === 1 ? "correction" : "corrections"}` : "Nothing changed");
  }, [state?.ok, state?.changed]);
  useEffect(() => { setValues(Object.fromEntries(EDIT_FIELDS.map((f) => [f, original[f] ?? ""]))); }, [original]);

  if (deleted) return <EmptyState icon={TriangleAlert} title="Lead is in the recycle bin">Restore it before correcting it.</EmptyState>;
  const overwritten = (history ?? []).filter((h) => h.overwritten);

  return (
    <div className="divide-y divide-border">
      <form onSubmit={onSubmit} noValidate className="px-5 py-4">
        <input type="hidden" name="_original" value={JSON.stringify(original)} />
        <p className="mb-3 text-[12.5px] text-muted">
          Corrections go through the same intake as Witty and keep the old value. Witty may still overwrite a field it captures
          later in the chat; the history below shows when that happens.
        </p>
        {EDIT_GROUPS.map((g) => (
          <fieldset key={g.title} className="mb-4">
            <legend className="mb-2 text-[11px] font-medium uppercase tracking-wider text-subtle">{g.title}</legend>
            <div className="grid gap-3 sm:grid-cols-2">
              {g.fields.map((f) => {
                const props = {
                  name: f, value: values[f] ?? "", "aria-invalid": Boolean(e[f]),
                  onChange: (x: React.ChangeEvent<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>) => setValues((v) => ({ ...v, [f]: x.target.value })),
                };
                const changed = dirty.includes(f);
                return (
                  <label key={f} className={cn("block space-y-1", f === "Comments" && "sm:col-span-2")}>
                    <span className={cn("text-[12px]", changed ? "font-medium text-fg" : "text-muted")}>{FIELD_LABEL[f]}{changed && " · changed"}</span>
                    {f === "lead_status" ? (
                      <select {...props} className={cn(field, "h-9")}>
                        {!original.lead_status && <option value="">Not classified</option>}
                        {CLASSIFICATIONS.map((c) => <option key={c} value={c}>{humanize(c)}</option>)}
                      </select>
                    ) : f === "Comments" ? (
                      <textarea {...props} rows={3} maxLength={2000} className={cn(field, "py-2")} />
                    ) : (
                      <input {...props} type={f === "email_id" ? "email" : "text"} inputMode={["academic_score_pct", "work_experience_years_num", "annual_budget_inr"].includes(f) ? "decimal" : undefined}
                        className={cn(field, "h-9")} />
                    )}
                    {e[f] && <span className="text-xs text-danger">{e[f]}</span>}
                  </label>
                );
              })}
            </div>
          </fieldset>
        ))}
        <label className="block space-y-1">
          <span className="text-[12px] text-muted">Why (kept with each change)</span>
          <input name="reason" maxLength={300} placeholder="e.g. student corrected their name on the call" className={cn(field, "h-9")} aria-invalid={Boolean(e.reason)} />
          {e.reason && <span className="text-xs text-danger">{e.reason}</span>}
        </label>
        <div className="mt-3 flex items-center justify-end gap-3">
          {state?.error && <span role="alert" className="mr-auto text-[13px] text-danger">{state.error}</span>}
          {dirty.length > 0 && (
            <Button type="button" size="sm" variant="ghost" onClick={() => setValues(Object.fromEntries(EDIT_FIELDS.map((f) => [f, original[f] ?? ""])))}>Undo changes</Button>
          )}
          <Button type="submit" size="sm" disabled={pending || dirty.length === 0}>
            {pending && <LoaderCircle className="size-3.5 animate-spin" />} Save {dirty.length > 0 ? `${dirty.length} ${dirty.length === 1 ? "change" : "changes"}` : ""}
          </Button>
        </div>
      </form>

      <section className="px-5 py-4">
        <h3 className="mb-2 flex items-center gap-1.5 text-[11px] font-medium uppercase tracking-wider text-subtle"><History className="size-3.5" /> Field history</h3>
        {overwritten.length > 0 && (
          <p className="mb-3 flex items-start gap-2 rounded-lg border border-warning/25 bg-warning-bg px-3 py-2 text-[12.5px] text-warning">
            <TriangleAlert className="mt-0.5 size-3.5 shrink-0" />
            {overwritten.length === 1 ? "One correction was" : `${overwritten.length} corrections were`} written over afterwards ({overwritten.map((h) => FIELD_LABEL[h.field as EditField] ?? h.field).join(", ")}).
          </p>
        )}
        {history === null ? (
          <p className="text-[13px] text-muted">The history could not be loaded.</p>
        ) : history.length === 0 ? (
          <p className="text-[13px] text-muted">No corrections yet.</p>
        ) : (
          <ul className="space-y-2.5 text-[13px]">
            {history.map((h) => (
              <li key={h.id}>
                <p className="text-fg">
                  <span className="font-medium">{FIELD_LABEL[h.field as EditField] ?? h.field}</span>{" "}
                  <span className="text-muted line-through decoration-subtle/60">{h.old ?? "empty"}</span> → <span>{h.new}</span>
                </p>
                <p className="text-[12px] text-subtle">
                  <time dateTime={h.at} title={formatDateTime(h.at)}>{relativeTime(h.at)}</time> · {h.reason}
                  {h.overwritten && <span className="text-warning"> · now “{h.current ?? "empty"}”{h.updated_by ? ` (by ${humanize(h.updated_by)})` : ""}</span>}
                </p>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
