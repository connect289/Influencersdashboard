"use client";
import { useEffect, useState, useTransition } from "react";
import Link from "next/link";
import { LoaderCircle, Play, Route } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { Notice } from "@/components/ui/Notice";
import { LANE_LABEL, OUTCOME_LABEL, type Decision } from "@/lib/routing";
import { routeLeadNow, simulateLead } from "./actions";
import { DecisionView } from "./DecisionView";

/** What "Route this lead now" would do, from the preview's destination; null when nothing can be routed from here. */
function routeNowText(d: Decision): string | null {
  if (d.already_routed || d.outcome === "with_partner" || d.outcome === "re-enquired") return null;
  switch (d.destination) {
    case "partner":
      return `Routing now records the allocation and sends the lead to ${d.partner_name}${d.is_test ? "'s sandbox" : ""} within seconds; the student is told once the partner's hold window passes.`;
    case "not_passed":
      return "Routing now records the lead as not passed; it then shows in the Leads list's Not passed view.";
    case "in_house":
      return `Routing now hands the lead to ${LANE_LABEL[d.b2c_lane ?? "sales"] ?? "B2C"} with this reason. B2B sends the student no message.`;
    case "consent_request":
      return "Routing now asks the student for partner-sharing consent (a one-tap message from Witty's or the B2C number) and waits up to 48 hours. Partners see the lead only after a YES; no answer sends it to B2C nurture.";
    case "consent_pending":
    case "consent_requested":
    case "none":
      return null;
  }
}

/** The toast after a real route, by what the engine did. */
function routedToast(d: Decision): string {
  switch (d.destination) {
    case "partner": return `Routed to ${d.partner_name} (${d.reference ?? "—"})`;
    case "not_passed": return "Recorded as not passed";
    case "consent_requested": return d.consent_request?.created || d.consent_request?.existing ? "Consent requested from the student; the lead is routed once they say YES" : "Consent could not be requested";
    case "consent_pending": return "Still waiting for the student's consent answer";
    case "none": return d.outcome === "test_lead" ? "Test lead: nothing was routed" : "Nothing was routed";
    case "consent_request": return "Nothing was routed";
    default: return `Handed to ${LANE_LABEL[d.b2c_lane ?? "sales"] ?? "B2C"}`;
  }
}

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

  const routeText = d ? routeNowText(d) : null;
  const outcomeNote = d && d.outcome && d.outcome !== "decided" ? OUTCOME_LABEL[d.outcome] ?? d.outcome : null;

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
        <p className="basis-full text-[12px] text-subtle">A simulation runs the rules R1–R9 and the scoring at this moment and writes nothing: no allocation, no consent request, no message. Routing for real happens only through the button under the result.</p>
      </form>
      {error && <Notice tone="error">{error}</Notice>}
      {d && (
        <>
          <DecisionView d={d} />
          {!d.committed && outcomeNote && (
            <p className="text-[12.5px] text-muted">Preview outcome: <span className="font-medium text-fg">{outcomeNote}</span>. Nothing was written.</p>
          )}
          {routeText && (
            <div className="flex flex-wrap items-center justify-end gap-3 border-t border-border pt-4">
              <p className="mr-auto text-[12.5px] text-muted">{routeText}</p>
              <Button size="sm" variant={d.destination === "partner" ? "primary" : "secondary"} onClick={() => setConfirm(true)}>
                <Route className="size-3.5" /> {d.destination === "consent_request" ? "Ask for consent and route" : "Route this lead now"}
              </Button>
            </div>
          )}
          {!routeText && !d.committed && d.destination === "none" && d.outcome === "test_lead" && (
            <p className="border-t border-border pt-4 text-[12.5px] text-muted">Test leads are never routed from here (R1). Open the lead to route it to a partner sandbox or send a test hand-off to B2C.</p>
          )}
        </>
      )}
      <ConfirmDialog
        open={confirm}
        onClose={() => setConfirm(false)}
        title={d?.destination === "consent_request" ? "Ask the student for consent?" : "Route this lead now?"}
        confirmLabel={d?.destination === "consent_request" ? "Ask and route" : "Route now"}
        reason={{ label: "Note for the audit log", placeholder: "e.g. test lead for Acme sandbox" }}
        onConfirm={async (note) => {
          if (!d) return;
          const res = await routeLeadNow(d.lead_id, note);
          if (!res.ok) return res.error;
          setD(res.decision);
          toast.success(routedToast(res.decision));
        }}
      >
        The engine runs again at this moment, so the result can differ from the simulation if something changed. Witty keeps chatting until a partner accepts the lead or a B2C counsellor is assigned.
      </ConfirmDialog>
    </div>
  );
}
