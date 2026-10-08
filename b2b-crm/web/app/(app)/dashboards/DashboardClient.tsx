"use client";
import { useState, useTransition } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { Copy, Home, LoaderCircle, Plus, Printer, X } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { DIM_LABEL, PERIOD_LABEL, PERIODS, type Period } from "@/lib/analytics";
import { archiveDashboard, copyDashboard, saveView, setHomeDashboard } from "./actions";

const field = "h-8 rounded-lg border border-border bg-surface px-2 text-[12.5px] text-fg focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30";

/** Dashboard-wide period and filters, kept in the URL so every view is a link. */
export function DashboardControls({ period, filters, dims, partners = {} }: { period: Period; filters: Record<string, string[]>; dims: string[]; partners?: Record<string, string> }) {
  const router = useRouter();
  const sp = useSearchParams();
  const [dim, setDim] = useState(dims[0] ?? "");
  const [val, setVal] = useState("");
  const go = (p: Period, f: Record<string, string[]>) => {
    const q = new URLSearchParams(sp.toString());
    q.set("period", p);
    if (Object.keys(f).length) q.set("filters", JSON.stringify(f)); else q.delete("filters");
    router.push(`?${q.toString()}`);
  };
  return (
    <div className="mb-5 flex flex-wrap items-center gap-2">
      <select value={period} onChange={(e) => go(e.target.value as Period, filters)} className={field} aria-label="Period">
        {PERIODS.map((p) => <option key={p} value={p}>{PERIOD_LABEL[p]}</option>)}
      </select>
      {Object.entries(filters).map(([k, vs]) => (
        <span key={k} className="inline-flex items-center gap-1 rounded-lg border border-border bg-surface-2 px-2 py-1 text-[12px]">
          <span className="text-subtle">{DIM_LABEL[k] ?? k}:</span> <span className="max-w-[180px] truncate text-fg">{vs.map((v) => (k === "partner" ? partners[v] ?? `#${v}` : v)).join(", ")}</span>
          <button type="button" aria-label={`Remove ${k} filter`} className="text-subtle hover:text-fg" onClick={() => { const f = { ...filters }; delete f[k]; go(period, f); }}><X className="size-3" /></button>
        </span>
      ))}
      {dims.length > 0 && (
        <form className="flex items-center gap-1" onSubmit={(e) => { e.preventDefault(); const vs = val.split(",").map((x) => x.trim()).filter(Boolean); if (dim && vs.length) { go(period, { ...filters, [dim]: vs }); setVal(""); } }}>
          <select value={dim} onChange={(e) => setDim(e.target.value)} className={field} aria-label="Filter by">
            {dims.map((d) => <option key={d} value={d}>{DIM_LABEL[d] ?? d}</option>)}
          </select>
          {dim === "partner" && Object.keys(partners).length > 0
            ? <select value={val} onChange={(e) => setVal(e.target.value)} className={`${field} w-44`} aria-label="Partner"><option value="">Choose</option>{Object.entries(partners).map(([id, n]) => <option key={id} value={id}>{n}</option>)}</select>
            : <input value={val} onChange={(e) => setVal(e.target.value)} placeholder="value, value" className={`${field} w-36`} aria-label="Filter values" />}
          <Button type="submit" size="sm" variant="secondary"><Plus className="size-3.5" /> Filter</Button>
        </form>
      )}
    </div>
  );
}

export function DashboardActions({ id, isDefault, isHome }: { id: number; isDefault: boolean; isHome: boolean }) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const [archive, setArchive] = useState(false);
  return (
    <div className="flex flex-wrap gap-2">
      <Button size="sm" variant="secondary" disabled={busy} onClick={() => start(async () => {
        const r = await copyDashboard(id);
        if (!r.ok) { toast.error(r.error); return; }
        toast.success("Copied: you can edit it now");
        router.push(`/dashboards/${r.id}/edit`);
      })}>{busy ? <LoaderCircle className="size-3.5 animate-spin" /> : <Copy className="size-3.5" />} Duplicate</Button>
      {!isDefault && <Button size="sm" variant="secondary" onClick={() => router.push(`/dashboards/${id}/edit`)}>Edit</Button>}
      <Button size="sm" variant="secondary" disabled={busy} onClick={() => start(async () => {
        const err = await setHomeDashboard(isHome ? null : id);
        if (err) toast.error(err); else toast.success(isHome ? "The Command Center is the home screen again" : "This is now your home screen");
      })}><Home className="size-3.5" /> {isHome ? "Unset home" : "Set as home"}</Button>
      <Button size="sm" variant="secondary" onClick={() => window.print()}><Printer className="size-3.5" /> Print / PDF</Button>
      {!isDefault && <Button size="sm" variant="secondary" onClick={() => setArchive(true)}>Archive</Button>}
      <ConfirmDialog open={archive} onClose={() => setArchive(false)} title="Archive this dashboard" confirmLabel="Archive" tone="danger"
        onConfirm={async () => { const err = await archiveDashboard(id); if (!err) { toast.success("Archived"); router.push("/dashboards"); } return err; }}>
        <p className="text-[13px] text-muted">It disappears from the gallery. Schedules that send it stop.</p>
      </ConfirmDialog>
    </div>
  );
}

export function SaveViewButton({ metric, filters, period }: { metric: string; filters: Record<string, string[]>; period: string }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <Button size="sm" variant="secondary" onClick={() => setOpen(true)}>Save as view</Button>
      <ConfirmDialog open={open} onClose={() => setOpen(false)} title="Save this list as a view" confirmLabel="Save" reason={{ label: "Name", placeholder: "e.g. Duplicates this month, Acme" }}
        onConfirm={async (name) => { const err = await saveView(name, metric, filters, period); if (!err) toast.success("Saved: it is listed under Dashboards → Saved views"); return err; }} />
    </>
  );
}
