"use client";
import { useEffect, useState, useTransition } from "react";
import Link from "next/link";
import { LoaderCircle, Play, Route } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { Notice } from "@/components/ui/Notice";
import type { Decision } from "@/lib/routing";
import { routeLeadNow, simulateLead } from "./actions";
import { DecisionView } from "./DecisionView";

/** Run the engine on one lead without sending anything; then, if wanted, route it for real. */
export function Simulator({ initialLead }: { initialLead: number | null }) {
  const [id, setId] = useState(initialLead ? String(initialLead) : "");
  const [d, setD] = useState<Decision | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const [confirm, setConfirm] = useState(false);

  const run = (leadId: string) => {
    setError(null);
    if (!/^\d{1,15}$/.test(leadId)) { setError("Enter a lead ID (the number in the Leads list)."); return; }
    start(async () => {
      const res = await simulateLead(Number(leadId));
      if (!res.ok) { setD(null); setError(res.error); return; }
      setD(res.decision);
    });
  };

  // Simulate the lead from the URL once on arrival (run is recreated every render; the lead id is what matters).
  useEffect(() => { if (initialLead) run(String(initialLead)); }, [initialLead]);

  return (
    <div className="space-y-5">
      <form onSubmit={(e) => { e.preventDefault(); run(id.trim()); }} className="flex flex-wrap items-end gap-3">
        <label className="space-y-1.5">
          <span className="block text-[13px] font-medium text-fg">Lead ID</span>
          <input value={id} onChange={(e) => setId(e.target.value)} inputMode="numeric" maxLength={15} placeholder="e.g. 1218"
            className="h-9 w-40 rounded-lg border border-border bg-surface px-3 font-mono text-[13px] text-fg focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30" />
        </label>
        <Button type="submit" size="sm" disabled={pending}>{pending ? <LoaderCircle className="size-3.5 animate-spin" /> : <Play className="size-3.5" />} Simulate</Button>
        {d && <Link href={`/leads?lead=${d.lead_id}`} className="pb-2 text-[13px] text-info hover:underline">Open the lead</Link>}
      </form>
      {error && <Notice tone="error">{error}</Notice>}
      {d && (
        <>
          <DecisionView d={d} />
          {!d.already_routed && (
            <div className="flex flex-wrap items-center justify-end gap-3 border-t border-border pt-4">
              <p className="mr-auto text-[12.5px] text-muted">
                {d.destination === "partner"
                  ? `Routing now records the allocation and queues the push to ${d.partner_name}${d.is_test ? "'s sandbox" : ""} (pushes start with the push adapter build).`
                  : d.destination === "not_passed"
                    ? "Routing now records the lead as not passed; it then shows in the Leads list's Not passed view."
                    : `Routing now hands the lead to ${d.b2c_lane === "nurture" ? "B2C nurture" : "B2C sales"} with this reason. B2B sends the student no message.`}
              </p>
              <Button size="sm" variant={d.destination === "partner" ? "primary" : "secondary"} onClick={() => setConfirm(true)}>
                <Route className="size-3.5" /> Route this lead now
              </Button>
            </div>
          )}
        </>
      )}
      <ConfirmDialog
        open={confirm}
        onClose={() => setConfirm(false)}
        title="Route this lead now?"
        confirmLabel="Route now"
        reason={{ label: "Note for the audit log", placeholder: "e.g. test lead for Acme sandbox" }}
        onConfirm={async (note) => {
          if (!d) return;
          const res = await routeLeadNow(d.lead_id, note);
          if (!res.ok) return res.error;
          setD(res.decision);
          toast.success(res.decision.destination === "partner" ? `Routed to ${res.decision.partner_name} (${res.decision.reference})`
            : res.decision.destination === "not_passed" ? "Recorded as not passed" : `Handed to ${res.decision.b2c_lane === "nurture" ? "B2C nurture" : "B2C sales"}`);
        }}
      >
        The engine runs again at this moment, so the result can differ from the simulation if something changed. Witty stops chatting with the lead once it is routed to a partner or B2C.
      </ConfirmDialog>
    </div>
  );
}
