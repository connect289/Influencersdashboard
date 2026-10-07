"use client";
import { useState } from "react";
import Link from "next/link";
import { Clock, Zap } from "lucide-react";
import { toast } from "sonner";
import { Badge, Card, CardHeader } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { cn } from "@/components/ui/cn";
import { formatDateTime, relativeTime } from "@/lib/format";
import type { SyncCadence } from "@/lib/b2c-link";
import { saveDelivery, saveSyncInterval } from "./actions";

function inMinutes(iso: string): string {
  const m = Math.round((Date.parse(iso) - Date.now()) / 60000);
  return m <= 0 ? "any moment" : `in ${m} min`;
}

/** Real time while a connection is integrated and tested; every sync interval (15 minutes) in production, to save paid API calls. */
export function CadenceCard({ c }: { c: SyncCadence }) {
  const [dialog, setDialog] = useState<"delivery" | "interval" | null>(null);
  const [minutes, setMinutes] = useState(String(c.interval_minutes));
  const batched = c.b2c.delivery === "batched";
  const m = c.interval_minutes;
  return (
    <Card className="min-w-0" id="cadence">
      <CardHeader title="Sync cadence"
        description={`Real time while a connection is being integrated and tested. Once it is tested, it syncs every ${m} minutes to keep paid API calls down. Test leads always sync in real time, so testing can go on.`} />
      <div className="grid gap-px border-t border-border bg-border md:grid-cols-2">
        <div className="space-y-2 bg-surface px-5 py-4 text-[12.5px]">
          <p className="flex items-center gap-2 font-medium text-fg">B2C CRM
            {batched ? <Badge tone="success"><Clock className="size-3" /> Every {m} minutes</Badge> : <Badge tone="warning"><Zap className="size-3" /> Real time (testing)</Badge>}</p>
          {batched ? (
            <p className="text-muted">Changes go in one batch webhook per {m} minutes{c.b2c.next_batch_at ? <>; next <span title={formatDateTime(c.b2c.next_batch_at)}>{inMinutes(c.b2c.next_batch_at)}</span></> : null}
              {c.b2c.waiting ? <>, {c.b2c.waiting} {c.b2c.waiting === 1 ? "lead" : "leads"} waiting</> : null}.
              {c.b2c.last_batch_at && <> Last batch {relativeTime(c.b2c.last_batch_at)}: {c.b2c.last_batch_leads ?? 0} leads.</>}</p>
          ) : <p className="text-muted">Every change goes out within seconds, one webhook per change. Switch once the B2C CRM is fully integrated and tested.</p>}
          <Button size="sm" variant={batched ? "secondary" : "primary"} onClick={() => setDialog("delivery")}>
            {batched ? "Back to real time" : `Switch to every ${m} minutes`}</Button>
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
      <ConfirmDialog open={dialog === "delivery"} onClose={() => setDialog(null)} confirmLabel={batched ? "Switch to real time" : "Switch"}
        title={batched ? "Back to real-time sync for the B2C CRM?" : `Sync the B2C CRM every ${m} minutes?`}
        reason={{ label: "Reason (kept in the settings history)", placeholder: batched ? "e.g. testing a new B2C CRM release" : "e.g. integration tested end to end" }}
        onConfirm={async (reason) => { const e = await saveDelivery(batched ? "realtime" : "batched", reason); if (!e) toast.success("Saved"); return e; }}>
        {batched ? <p>Every change goes out again within seconds, one webhook per change. Use it only while testing: it makes many more calls.</p>
          : <p>Changes to real students then reach the B2C CRM in one batch every {m} minutes (each lead once, at its newest version); test leads stay real time.
              The B2C CRM must handle <code>b2c.leads_batch</code> (docs/b2c-contract.md §1). Its reads and writes through the API stay immediate.</p>}
      </ConfirmDialog>
      <ConfirmDialog open={dialog === "interval"} onClose={() => setDialog(null)} confirmLabel="Save" title={`Sync every ${minutes} minutes?`}
        reason={{ label: "Reason (kept in the settings history)" }}
        onConfirm={async (reason) => { const e = await saveSyncInterval(Number(minutes), reason); if (!e) toast.success("Saved"); return e; }}>
        <p>Applies to B2C CRM batches and to live partner CRM polling (partners with their own polling minutes keep them).</p>
      </ConfirmDialog>
    </Card>
  );
}
