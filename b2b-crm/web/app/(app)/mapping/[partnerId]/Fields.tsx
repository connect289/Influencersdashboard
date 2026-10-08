"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { ArrowLeftRight, ArrowLeft, ArrowRight, Columns3, Pencil, Plus, Sparkles, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { Badge, EmptyState } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { cn } from "@/components/ui/cn";
import { DIRECTION_LABEL, formatChain, knownFields, parseChain, TRANSFORM_HELP, type Direction, type FieldRule, type Studio } from "@/lib/mapping";
import { removeRule, resolveQueue, saveRule } from "./actions";
import { field, Label, Modal } from "@/components/ui/Modal";

type Draft = Partial<FieldRule> & { canonical_key: string };

const DirIcon = ({ d }: { d: Direction }) => d === "both" ? <ArrowLeftRight className="size-3.5" /> : d === "in" ? <ArrowLeft className="size-3.5" /> : <ArrowRight className="size-3.5" />;

function FieldRuleDialog({ studio, rule, onClose }: { studio: Studio; rule: Draft; onClose: () => void }) {
  const router = useRouter();
  const ed = studio.editing!;
  const [r, setR] = useState<Draft>(rule);
  const [inText, setInText] = useState(formatChain(rule.transforms));
  const [outText, setOutText] = useState(formatChain(rule.out_transforms));
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const c = studio.canonical.find((x) => x.key === r.canonical_key);
  const dirs: Direction[] = !c ? ["both", "in", "out"] : (["both", "in", "out"] as Direction[]).filter((d) => (d !== "out" && d !== "both" || c.outbound) && (d !== "in" && d !== "both" || c.inbound));
  const dir = r.direction && dirs.includes(r.direction) ? r.direction : dirs[0] ?? "in";
  const known = knownFields(studio).map((f) => f.name);
  const set = (k: keyof FieldRule, v: unknown) => setR((cur) => ({ ...cur, [k]: v }));

  const save = async () => {
    const tin = parseChain(inText, studio.transform_ops), tout = parseChain(outText, studio.transform_ops);
    if (!tin.ok) { setError(`Partner → Eduwit: ${tin.error}`); return; }
    if (!tout.ok) { setError(`Eduwit → partner: ${tout.error}`); return; }
    setPending(true); setError(null);
    const res = await saveRule(studio.partner.id, "field", {
      id: r.id ?? null, profile_id: ed.id, partner_field: r.not_available ? null : r.partner_field ?? "", canonical_key: r.canonical_key, direction: dir,
      transforms: dir === "out" ? [] : tin.chain, out_transforms: dir === "in" ? [] : tout.chain, trusted: Boolean(r.trusted) && c?.owner !== "b2b",
      required: Boolean(r.required) && dir !== "in", not_available: Boolean(r.not_available), note: r.note ?? null,
    });
    setPending(false);
    if (!res.ok) { setError(res.error); return; }
    toast.success("Field rule saved");
    onClose(); router.refresh();
  };

  return (
    <Modal open onClose={onClose} title={r.id ? "Edit field rule" : "Map a field"} error={error} pending={pending} onSubmit={save} wide>
      <div className="grid gap-3 sm:grid-cols-2">
        <Label text="Eduwit field">
          <select value={r.canonical_key} onChange={(e) => set("canonical_key", e.target.value)} className={field}>
            <option value="">Choose…</option>
            {(["lead", "sales"] as const).map((g) => (
              <optgroup key={g} label={g === "lead" ? "Lead (student and interest)" : "Sales (from the partner)"}>
                {studio.canonical.filter((x) => x.grp === g).map((x) => <option key={x.key} value={x.key}>{x.label}{x.required_in || x.required_out ? " *" : ""}</option>)}
              </optgroup>
            ))}
          </select>
        </Label>
        <Label text="Partner field" hint={r.not_available ? "Marked as not available at this partner" : undefined}>
          <input value={r.partner_field ?? ""} onChange={(e) => set("partner_field", e.target.value)} disabled={Boolean(r.not_available)} list="partner-fields" className={cn(field, "font-mono")} maxLength={200} />
          <datalist id="partner-fields">{known.map((k) => <option key={k} value={k} />)}</datalist>
        </Label>
      </div>
      {c && (
        <p className="text-[12px] text-muted">
          {c.data_type === "picklist" ? `Picklist (${(c.allowed ?? studio.lost_reasons).join(", ")}): map the partner's values in the Values tab.` : `Type: ${c.data_type}.`}
          {c.owner === "witty" && " Witty owns this field: partner data fills it only when it is empty and the partner is trusted."}
          {c.lead_column ? ` Written to the lead's ${c.lead_column}.` : " Kept on the allocation (no lead column)."}
        </p>
      )}
      <label className="flex items-center gap-2 text-[13px]">
        <input type="checkbox" checked={Boolean(r.not_available)} onChange={(e) => set("not_available", e.target.checked)} className="accent-[var(--primary)]" />
        The partner does not have this field (counts as covered for go-live)
      </label>
      {!r.not_available && (
        <>
          <Label text="Direction">
            <div className="flex flex-wrap gap-2">
              {dirs.map((d) => (
                <button key={d} type="button" onClick={() => set("direction", d)}
                  className={cn("flex items-center gap-1.5 rounded-lg border px-3 py-1.5 text-[13px]", dir === d ? "border-amber bg-amber/10 text-fg" : "border-border text-muted hover:text-fg")}>
                  <DirIcon d={d} /> {DIRECTION_LABEL[d]}
                </button>
              ))}
            </div>
          </Label>
          {dir !== "out" && (
            <Label text="Transforms, partner → Eduwit" hint="Separated by |. Example: trim | amount">
              <input value={inText} onChange={(e) => setInText(e.target.value)} className={cn(field, "font-mono")} placeholder="none" />
            </Label>
          )}
          {dir !== "in" && (
            <Label text="Transforms, Eduwit → partner" hint="Example: join(with='specialization', sep=' - ')">
              <input value={outText} onChange={(e) => setOutText(e.target.value)} className={cn(field, "font-mono")} placeholder="none" />
            </Label>
          )}
          <details className="text-[12px] text-muted">
            <summary className="cursor-pointer">Available transforms</summary>
            <ul className="mt-1 grid gap-x-4 sm:grid-cols-2">{studio.transform_ops.map((o) => <li key={o}><span className="font-mono text-fg">{o}</span>: {TRANSFORM_HELP[o]}</li>)}</ul>
          </details>
          <div className="flex flex-wrap gap-x-6 gap-y-2">
            {c?.owner === "witty" && dir !== "out" && (
              <label className="flex items-center gap-2 text-[13px]">
                <input type="checkbox" checked={Boolean(r.trusted)} onChange={(e) => set("trusted", e.target.checked)} className="accent-[var(--primary)]" /> Trusted: may fill Eduwit&apos;s empty value
              </label>
            )}
            {dir !== "in" && (
              <label className="flex items-center gap-2 text-[13px]">
                <input type="checkbox" checked={Boolean(r.required)} onChange={(e) => set("required", e.target.checked)} className="accent-[var(--primary)]" /> The partner&apos;s API requires it
              </label>
            )}
          </div>
        </>
      )}
      <Label text="Note" hint="Optional"><input value={r.note ?? ""} onChange={(e) => set("note", e.target.value)} className={field} maxLength={300} /></Label>
    </Modal>
  );
}

export function FieldsPanel({ studio }: { studio: Studio }) {
  const router = useRouter();
  const ed = studio.editing;
  const canEdit = ed?.status === "draft";
  const [dialog, setDialog] = useState<Draft | null>(null);
  const [remove, setRemove] = useState<FieldRule | null>(null);
  const [custom, setCustom] = useState<{ id: number; name: string } | null>(null);
  if (!ed) return <EmptyState icon={Columns3} title="No mapping yet">Start a draft to map this partner&apos;s fields.</EmptyState>;

  const fields = knownFields(studio);
  const label = (k: string) => studio.canonical.find((c) => c.key === k)?.label ?? k;
  const missingIn = ed.coverage.items.filter((i) => i.group === "in" && !i.done);
  const missingOut = ed.coverage.items.filter((i) => i.group === "out" && !i.done);
  const markNA = async (key: string) => {
    const r = await saveRule(studio.partner.id, "field", { profile_id: ed.id, canonical_key: key, direction: "in", not_available: true });
    if (!r.ok) toast.error(r.error); else { toast.success(`${label(key)} marked as not available`); router.refresh(); }
  };

  return (
    <>
      {(missingIn.length > 0 || missingOut.length > 0) && (
        <div className="space-y-2 border-b border-border px-5 py-4">
          <p className="text-[13px] font-medium text-fg">Required for go-live, not mapped yet</p>
          <ul className="flex flex-wrap gap-2">
            {[...missingOut, ...missingIn].map((i) => (
              <li key={`${i.group}-${i.key}`} className="flex items-center gap-1.5 rounded-lg border border-warning/30 bg-warning-bg px-2.5 py-1 text-[12.5px] text-warning">
                {i.group === "out" ? <ArrowRight className="size-3.5" /> : <ArrowLeft className="size-3.5" />} {i.item}
                {canEdit && i.key && <Button size="sm" variant="ghost" onClick={() => setDialog({ canonical_key: i.key!, direction: i.group === "out" ? "out" : "in" })}>Map</Button>}
                {canEdit && i.key && i.group === "in" && <Button size="sm" variant="ghost" onClick={() => markNA(i.key!)}>Not available</Button>}
              </li>
            ))}
          </ul>
        </div>
      )}

      <div className="flex items-center justify-between gap-3 px-5 py-2.5">
        <p className="text-[12.5px] text-muted">Partner fields seen in the schema, in events and in the queue. Suggestions are never applied without you.</p>
        <Button size="sm" disabled={!canEdit} onClick={() => setDialog({ canonical_key: "" })}><Plus className="size-3.5" /> Field rule</Button>
      </div>
      {fields.length > 0 && (
        <div className="overflow-x-auto">
          <table className="w-full min-w-[760px] text-left text-[12.5px]">
            <thead className="text-[11px] uppercase tracking-wider text-subtle">
              <tr className="border-y border-border">
                <th scope="col" className="px-5 py-2 font-medium">Partner field</th>
                <th scope="col" className="px-3 py-2 font-medium">Sample values</th>
                <th scope="col" className="px-3 py-2 font-medium">Eduwit</th>
                <th scope="col" className="px-5 py-2"><span className="sr-only">Actions</span></th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {fields.map((f) => {
                const q = studio.queue.find((x) => x.kind === "field" && x.item.toLowerCase() === f.name.toLowerCase() && x.status === "open");
                return (
                  <tr key={f.name}>
                    <td className="px-5 py-2 font-mono text-[12px] text-fg">{f.name}</td>
                    <td className="max-w-[240px] truncate px-3 py-2 text-muted" title={f.values.join(", ")}>{f.values.slice(0, 4).join(", ") || "—"}</td>
                    <td className="px-3 py-2">
                      {f.rule ? <span className="flex items-center gap-1.5"><DirIcon d={f.rule.direction} /> {label(f.rule.canonical_key)}</span>
                        : f.custom ? <Badge>Kept as custom field</Badge>
                        : f.suggestion ? <span className="flex items-center gap-1.5 text-muted" title={f.suggestion.why}><Sparkles className="size-3.5 text-amber" /> {label(f.suggestion.key)}? <span className="tabular text-subtle">{Math.round(f.suggestion.confidence * 100)}%</span></span>
                        : <span className="text-subtle">Not mapped</span>}
                    </td>
                    <td className="whitespace-nowrap px-5 py-2 text-right">
                      {canEdit && !f.rule && (
                        <>
                          <Button size="sm" variant="ghost" onClick={() => setDialog({ canonical_key: f.suggestion?.key ?? "", partner_field: f.name })}>{f.suggestion ? "Accept…" : "Map"}</Button>
                          {q && !f.custom && <Button size="sm" variant="ghost" onClick={() => setCustom({ id: q.id, name: f.name })}>Keep as custom</Button>}
                        </>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      <div className="border-t border-border px-5 pb-1 pt-4"><p className="text-[13px] font-medium text-fg">Rules in this version <span className="tabular text-subtle">{ed.field_rules.length}</span></p></div>
      {ed.field_rules.length === 0 ? <EmptyState icon={Columns3} title="No field rules yet" /> : (
        <ul className="divide-y divide-border">
          {ed.field_rules.map((r) => (
            <li key={r.id} className="flex flex-wrap items-center gap-x-3 gap-y-1 px-5 py-2.5 text-[12.5px]">
              <span className="min-w-[180px] font-medium text-fg">{label(r.canonical_key)}</span>
              {r.not_available ? <Badge>Not available at this partner</Badge> : (
                <>
                  <span className="flex items-center gap-1 text-muted"><DirIcon d={r.direction} /> <span className="font-mono text-fg">{r.partner_field}</span></span>
                  {r.transforms.length > 0 && <span className="font-mono text-subtle" title="Partner → Eduwit">in: {formatChain(r.transforms)}</span>}
                  {r.out_transforms.length > 0 && <span className="font-mono text-subtle" title="Eduwit → partner">out: {formatChain(r.out_transforms)}</span>}
                  {r.trusted && <Badge tone="info">trusted</Badge>}
                  {r.required && <Badge tone="brand">required by partner</Badge>}
                </>
              )}
              {r.note && <span className="text-subtle">· {r.note}</span>}
              <span className="ml-auto">
                {canEdit && <>
                  <Button size="sm" variant="ghost" onClick={() => setDialog(r)} aria-label="Edit"><Pencil className="size-3.5" /></Button>
                  <Button size="sm" variant="ghost" onClick={() => setRemove(r)} aria-label="Remove"><Trash2 className="size-3.5" /></Button>
                </>}
              </span>
            </li>
          ))}
        </ul>
      )}

      {dialog && <FieldRuleDialog studio={studio} rule={dialog} onClose={() => setDialog(null)} />}
      <ConfirmDialog
        open={remove !== null}
        onClose={() => setRemove(null)}
        title="Remove this field rule from the draft?"
        tone="danger"
        confirmLabel="Remove"
        onConfirm={async () => {
          if (!remove) return;
          const r = await removeRule(studio.partner.id, "field", remove.id);
          if (!r.ok) return r.error;
          toast.success("Rule removed from the draft");
          router.refresh();
        }}
      />
      <ConfirmDialog
        open={custom !== null}
        onClose={() => setCustom(null)}
        title={`Keep “${custom?.name ?? ""}” as a custom field?`}
        confirmLabel="Keep as custom"
        reason={{ label: "Why", placeholder: "e.g. partner's internal score, not needed in Eduwit's model" }}
        onConfirm={async (note) => {
          if (!custom) return;
          const r = await resolveQueue(studio.partner.id, custom.id, "ignored", note);
          if (!r.ok) return r.error;
          toast.success("Kept as a custom field");
          router.refresh();
        }}
      >
        Its values stay on each lead&apos;s allocation under the partner&apos;s name, and it leaves the queue. Nothing is dropped.
      </ConfirmDialog>
    </>
  );
}
