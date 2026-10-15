"use client";
import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { formatDateTime, relativeTime } from "@/lib/format";
import type { DataProtection as DP } from "@/lib/integrations";
import { saveRetention } from "./actions";

const field = "h-9 w-28 rounded-lg border border-border bg-surface px-3 text-[13px] text-fg focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30";

/** M33c: the retention rules (what the nightly job erases and deletes) and the counts behind them. */
export function DataProtection({ d }: { d: DP }) {
  const [months, setMonths] = useState(d.settings.inactive_months === null ? "" : String(d.settings.inactive_months));
  const [days, setDays] = useState(d.settings.test_lead_days === null ? "" : String(d.settings.test_lead_days));
  const [confirm, setConfirm] = useState(false);
  const changed = months !== (d.settings.inactive_months === null ? "" : String(d.settings.inactive_months)) || days !== (d.settings.test_lead_days === null ? "" : String(d.settings.test_lead_days));
  return (
    <div className="divide-y divide-border">
      <dl className="grid grid-cols-2 gap-px bg-border sm:grid-cols-4">
        {[
          ["Erased so far", d.anonymised_total, "Leads whose personal data was removed (erasure requests, retention)"],
          ["Would be erased tonight", d.inactive_to_erase, "Inactive leads the retention rule covers"],
          ["Test leads to delete", d.test_leads_to_delete, "Older than the test-lead limit"],
          ["Opted out", d.opted_out_total, "Students who asked for no messages"],
        ].map(([l, v, h]) => (
          <div key={String(l)} className="bg-surface px-5 py-3" title={String(h)}>
            <dt className="text-[12px] text-muted">{l}</dt><dd className="tabular mt-0.5 text-xl font-semibold text-fg">{v as number}</dd>
          </div>
        ))}
      </dl>
      <div className="flex flex-wrap items-end gap-4 px-5 py-4 text-[13px]">
        <label className="flex flex-col gap-1 text-muted">Erase leads idle for (months)
          <input className={field} inputMode="numeric" value={months} onChange={(e) => setMonths(e.target.value.replace(/\D/g, "").slice(0, 3))} placeholder="off" />
        </label>
        <label className="flex flex-col gap-1 text-muted">Delete test leads after (days)
          <input className={field} inputMode="numeric" value={days} onChange={(e) => setDays(e.target.value.replace(/\D/g, "").slice(0, 3))} placeholder="off" />
        </label>
        <Button size="sm" disabled={!changed} onClick={() => setConfirm(true)}>Save rules</Button>
        <p className="basis-full text-[12px] text-subtle">
          Idle means no activity, update or contact for that long; leads with an enrolment or still with a partner or a counsellor are never erased. 6 to 120 months, empty to keep leads forever. The job runs nightly (02:15 IST), at most 200 erasures and 500 test deletions a night.
          {d.last_run ? <> Last run <span title={formatDateTime(d.last_run.at)}>{relativeTime(d.last_run.at)}</span>: {d.last_run.erased} erased, {d.last_run.test_deleted} test leads deleted{d.last_run.errors ? <span className="text-danger">, {d.last_run.errors} failed</span> : null}.</> : " It has not run yet."}
        </p>
      </div>
      <div className="px-5 py-3 text-[12.5px] text-muted">
        Erasure requests: {d.erasures.open} open, {d.erasures.done_30d} done in 30 days · Partners to tell about an erasure (90 days): {d.partner_notices_open} · Consents recorded in 30 days: {d.consents_30d}.
        Erasing a lead here removes its personal data from this CRM only: partner copies and Witty&rsquo;s chat history are removed by the steps in the operations runbook.
      </div>
      <ConfirmDialog open={confirm} onClose={() => setConfirm(false)} title="Change the retention rules?" confirmLabel="Save"
        reason={{ label: "Reason (kept in the settings history)", placeholder: "e.g. DPDP policy: 24 months" }}
        onConfirm={async (reason) => {
          const err = await saveRetention(months === "" ? null : Number(months), days === "" ? null : Number(days), reason);
          if (err) return err;
          toast.success("Retention rules saved"); setConfirm(false);
        }}>
        <p className="text-[13px] text-muted">{months === "" ? "Inactive leads are kept forever." : `Leads idle for ${months} months are erased nightly: ${d.inactive_to_erase} would go on the next run if the rule stays the same.`} {days === "" ? "Test leads are kept." : `Test leads older than ${days} days are deleted.`}</p>
      </ConfirmDialog>
    </div>
  );
}
