"use client";
import { useState } from "react";
import Link from "next/link";
import { LoaderCircle, RefreshCw, Search } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { Notice } from "@/components/ui/Notice";
import { formatDateTime } from "@/lib/format";
import { actorText, describeActivity, describeChanges, type LinkLead } from "@/lib/b2c-link";
import { inspectLead, resync } from "./actions";

const field = "h-9 w-40 rounded-lg border border-border bg-surface px-3 text-[13px] text-fg placeholder:text-subtle focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30";
const TONE: Record<string, "success" | "info" | "warning" | "danger" | "neutral"> = {
  delivered: "success", sending: "info", pending: "neutral", failed: "warning", dead: "danger", cancelled: "neutral",
  applied: "success", unchanged: "neutral", conflict: "warning", rejected: "danger",
};

/** One lead as the B2C CRM sees it: the record, its versions and deliveries, and what the B2C CRM wrote. */
export function LeadInspector({ initial }: { initial: number | null }) {
  const [id, setId] = useState(initial ? String(initial) : "");
  const [res, setRes] = useState<LinkLead | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<"check" | "resend" | null>(null);

  const load = async () => {
    setBusy("check"); setError(null);
    try { const r = await inspectLead(Number(id)); if (r.ok) setRes(r.data); else { setRes(null); setError(r.error); } } finally { setBusy(null); }
  };
  const resend = async () => {
    setBusy("resend");
    try {
      const r = await resync(Number(id));
      if (!r.ok) { toast.error(r.error); return; }
      toast.success("Sent again as a new version");
      const x = await inspectLead(Number(id)); if (x.ok) setRes(x.data);
    } finally { setBusy(null); }
  };

  return (
    <div className="space-y-4 p-5">
      <form className="flex flex-wrap items-end gap-2" onSubmit={(e) => { e.preventDefault(); void load(); }}>
        <label className="space-y-1"><span className="block text-[13px] font-medium text-fg">Lead number</span>
          <input className={field} inputMode="numeric" value={id} placeholder="e.g. 1342" onChange={(e) => setId(e.target.value.replace(/\D/g, ""))} /></label>
        <Button type="submit" disabled={!id || Boolean(busy)}>{busy === "check" ? <LoaderCircle className="size-4 animate-spin" /> : <Search className="size-4" />} Inspect</Button>
        {res && <Button variant="secondary" disabled={Boolean(busy)} onClick={() => void resend()}>{busy === "resend" ? <LoaderCircle className="size-4 animate-spin" /> : <RefreshCw className="size-4" />} Send again</Button>}
      </form>
      {error && <Notice tone="error">{error}</Notice>}
      {res && (
        <>
          <div className="flex flex-wrap items-center gap-2 text-[13px]">
            <Link href={`/leads?lead=${res.lead_id}`} className="font-medium text-fg hover:underline">{res.name ?? `Lead #${res.lead_id}`}</Link>
            {res.held_by_b2c ? <Badge tone="success">Held by B2C</Badge> : <Badge>Not held by B2C</Badge>}
            {res.shared ? <Badge tone="info">In the B2C CRM&apos;s copy · version {res.version}</Badge> : <Badge>Not in the B2C CRM&apos;s copy</Badge>}
            {res.changed_at && <span className="text-muted">last sent {formatDateTime(res.changed_at)}{res.origin ? ` (${res.origin})` : ""}</span>}
          </div>
          <div className="grid gap-4 xl:grid-cols-[1.2fr_1fr]">
            <div className="min-w-0">
              <p className="mb-1.5 text-[12px] font-medium text-muted">Record as the B2C CRM receives it</p>
              <pre className="max-h-[520px] overflow-auto rounded-lg border border-border bg-surface-2 p-3 font-mono text-[11.5px] text-fg">{JSON.stringify(res.record, null, 2)}</pre>
            </div>
            <div className="min-w-0 space-y-4">
              <div>
                <p className="mb-1.5 text-[12px] font-medium text-muted">Deliveries</p>
                {res.deliveries.length === 0 ? <p className="text-[12.5px] text-subtle">None: the endpoint is off, or the lead was never shared.</p> : (
                  <ul className="divide-y divide-border rounded-lg border border-border text-[12.5px]">
                    {res.deliveries.map((d) => (
                      <li key={d.id} className="flex flex-wrap items-center gap-2 px-3 py-2">
                        <span className="text-fg">v{d.version}</span><span className="text-muted">{d.type.replace("b2c.lead_", "")}</span>
                        <Badge tone={TONE[d.status] ?? "neutral"}>{d.status}</Badge>
                        <span className="ml-auto text-subtle">{formatDateTime(d.delivered_at ?? d.created_at)}</span>
                        {d.error && <span className="w-full truncate text-[11.5px] text-danger" title={d.error}>{d.error}</span>}
                      </li>
                    ))}
                  </ul>
                )}
              </div>
              <div>
                <p className="mb-1.5 text-[12px] font-medium text-muted">Written by the B2C CRM</p>
                {res.writes.length === 0 ? <p className="text-[12.5px] text-subtle">Nothing yet.</p> : (
                  <ul className="divide-y divide-border rounded-lg border border-border text-[12.5px]">
                    {res.writes.map((w, i) => (
                      <li key={i} className="space-y-0.5 px-3 py-2">
                        <div className="flex flex-wrap items-center gap-2">
                          <span className="font-medium text-fg">{w.kind === "activity" ? "Activity" : "Update"}</span>
                          <Badge tone={TONE[w.status] ?? "neutral"}>{w.status}</Badge>
                          <span className="text-muted">{actorText(w.actor)}</span>
                          <span className="ml-auto text-subtle">{formatDateTime(w.at)}</span>
                        </div>
                        <p className="truncate text-muted" title={JSON.stringify(w.changes)}>{w.error ?? (w.kind === "activity" ? describeActivity(w.changes) : describeChanges(w.changes))}</p>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
