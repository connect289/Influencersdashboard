"use client";
import { useState } from "react";
import Link from "next/link";
import { Clock, Zap } from "lucide-react";
import { toast } from "sonner";
import { Badge, Card, CardHeader } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { cn } from "@/components/ui/cn";
import { relativeTime } from "@/lib/format";
import type { SyncCadence } from "@/lib/b2c-link";
import { saveSyncInterval } from "./actions";

/** Addendum 4: the B2C CRM is always served in real time, and its own changes come back in its 15-minute batch. The
 *  production interval below now applies to live partner CRM polling only. */
export function CadenceCard({ c }: { c: SyncCadence }) {
  const [dialog, setDialog] = useState<"interval" | null>(null);
  const [minutes, setMinutes] = useState(String(c.interval_minutes));
  const m = c.interval_minutes;
  return (
    <Card className="min-w-0" id="cadence">
      <CardHeader title="Sync cadence"
        description={`The B2C CRM always gets changes in real time. Live partner CRMs are polled every ${m} minutes to keep paid API calls down; sandboxes are polled more often while testing.`} />
      <div className="grid gap-px border-t border-border bg-border md:grid-cols-2">
        <div className="space-y-2 bg-surface px-5 py-4 text-[12.5px]">
          <p className="flex items-center gap-2 font-medium text-fg">B2C CRM <Badge tone="success"><Zap className="size-3" /> Real time</Badge></p>
          <p className="text-muted">Every hand-off, re-enquiry, consent request and change to a lead it holds reaches it within seconds (target: 5 seconds).
            Its own changes come back to us in one batch every 15 minutes; consent answers, opt-outs, erasure requests and route-to-partners come at once.</p>
          <p className="flex items-center gap-1.5 text-subtle"><Clock className="size-3" aria-hidden /> The 15-minute batched delivery is not offered for the B2C CRM (Addendum 4).</p>
        </div>
        <div className="space-y-2 bg-surface px-5 py-4 text-[12.5px]">
          <p className="font-medium text-fg">Partner CRMs</p>
          {c.partners.length === 0 ? <p className="text-muted">No partner CRM is polled yet.</p> : (
            <ul className="space-y-1.5">
              {c.partners.map((p) => (
                <li key={p.id} className="grid grid-cols-[minmax(0,1fr)_auto] gap-x-3">
                  <Link href={`/partners/${p.id}?tab=connection`} className="truncate text-fg hover:underline">{p.name}</Link>
                  <span className="text-right text-subtle">{p.last_poll_at ? relativeTime(p.last_poll_at) : ""}</span>
                  <span className={cn("col-span-2 text-[12px]", p.live ? "text-muted" : "text-subtle")}>
                    {!p.poll ? "webhooks only" : p.live ? `live, polled every ${p.live_minutes} min${p.own_minutes ? " (its own setting)" : ""}` : `testing: sandbox polled every ${p.sandbox_minutes} min`}</span>
                </li>
              ))}
            </ul>
          )}
          <p className="text-subtle">New leads are still pushed to their partner at once (one call per lead either way; speed to lead and the partner&apos;s SLA depend on it).</p>
        </div>
      </div>
      <div className="flex flex-wrap items-center gap-3 border-t border-border px-5 py-3 text-[12.5px]">
        <label htmlFor="sync-min" className="text-muted">Production sync interval</label>
        <input id="sync-min" inputMode="numeric" className="tabular h-8 w-16 rounded-lg border border-border bg-surface px-2 text-[13px] text-fg focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30"
          value={minutes} onChange={(e) => setMinutes(e.target.value.replace(/\D/g, "").slice(0, 2))} />
        <span className="text-muted">minutes (5 to 60)</span>
        <Button size="sm" variant="secondary" disabled={Number(minutes) === m || !minutes} onClick={() => setDialog("interval")}>Save</Button>
      </div>
      <ConfirmDialog open={dialog === "interval"} onClose={() => setDialog(null)} confirmLabel="Save" title={`Sync every ${minutes} minutes?`}
        reason={{ label: "Reason (kept in the settings history)" }}
        onConfirm={async (reason) => { const e = await saveSyncInterval(Number(minutes), reason); if (!e) toast.success("Saved"); return e; }}>
        <p>Applies to live partner CRM polling (partners with their own polling minutes keep them). The B2C CRM stays real time.</p>
      </ConfirmDialog>
    </Card>
  );
}
