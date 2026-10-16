"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Plus } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { applicationSave, documentAdd, enrollmentRecord } from "@/app/s/actions";
import { date, inr, istDay } from "@/lib/format";
import { APP_STATUS_LABEL } from "@/lib/labels";
import type { Application, Enrollment } from "@/lib/types";

type Mode = { kind: "app"; app?: Application } | { kind: "doc"; app: Application; item?: string } | { kind: "enrol"; app?: Application } | null;

/** Applications, document checklist and enrolment (spec B11). An enrolment needs the fee, the date and the proof. */
export function ApplicationsPanel({ leadId, apps, enrollments, canEdit, defaultProgramme, defaultUniversity }: {
  leadId: number; apps: Application[]; enrollments: Enrollment[]; canEdit: boolean; defaultProgramme: string | null; defaultUniversity: string | null;
}) {
  const [mode, setMode] = useState<Mode>(null);
  const close = () => setMode(null);
  return (
    <section className="panel">
      <header>
        <h3>Applications</h3>
        {canEdit && <button type="button" className="btn quiet sm" onClick={() => setMode({ kind: "app" })}><Plus className="icon s" aria-hidden />Add</button>}
      </header>
      <div className="body">
        {apps.length === 0 && <p className="note">No application yet. Adding one moves the lead to Applicant.</p>}
        {apps.map((a) => (
          <div key={a.id} className="card pad stack" style={{ gap: 8 }}>
            <div className="row between wrap">
              <div><b>{a.university}</b> · {a.programme}<div className="small muted">{a.application_ref ? `Application ID ${a.application_ref} · ` : ""}{APP_STATUS_LABEL[a.status] ?? a.status}</div></div>
              {canEdit && <button type="button" className="btn quiet sm" onClick={() => setMode({ kind: "app", app: a })}>Edit</button>}
            </div>
            {(a.fee_amount || a.fee_paid) && <div className="small">Fee {inr(a.fee_amount)} · paid {inr(a.fee_paid)}</div>}
            <div className="stack" style={{ gap: 4 }}>
              {Object.entries(a.checklist ?? {}).map(([item, state]) => (
                <div key={item} className="row between small">
                  <span>{item}</span>
                  <span className="row" style={{ gap: 6 }}>
                    <span className={`chip ${state === "received" ? "ok" : "line"}`}>{state === "received" ? "Received" : "Pending"}</span>
                    {canEdit && state !== "received" && <button type="button" className="btn quiet sm" onClick={() => setMode({ kind: "doc", app: a, item })}>Upload</button>}
                  </span>
                </div>
              ))}
            </div>
            {canEdit && !enrollments.some((e) => e.status !== "cancelled") && (
              <button type="button" className="btn ghost sm" style={{ justifySelf: "start" }} onClick={() => setMode({ kind: "enrol", app: a })}>Record enrolment</button>
            )}
          </div>
        ))}
        {enrollments.map((e) => (
          <div key={e.id} className="banner info">
            <div>
              <b>Enrolled: {e.university} · {e.programme}</b> on {date(e.enrolled_on)} · fee {inr(e.fee)}, paid {inr(e.fee_paid)} ·{" "}
              {e.status === "verified" ? <span className="chip ok">Verified by the Admin</span> : e.status === "reported" ? <span className="chip risk">Waiting for the Admin</span> : e.status}
              {e.note && <div className="small">{e.note}</div>}
            </div>
          </div>
        ))}
        {canEdit && apps.length === 0 && !enrollments.length && (
          <button type="button" className="btn ghost sm" style={{ justifySelf: "start" }} onClick={() => setMode({ kind: "enrol" })}>Record enrolment</button>
        )}
      </div>
      {mode?.kind === "app" && <AppSheet leadId={leadId} app={mode.app} programme={defaultProgramme} university={defaultUniversity} onClose={close} />}
      {mode?.kind === "doc" && <DocSheet leadId={leadId} app={mode.app} item={mode.item} onClose={close} />}
      {mode?.kind === "enrol" && <EnrolSheet leadId={leadId} app={mode.app} programme={defaultProgramme} university={defaultUniversity} onClose={close} />}
    </section>
  );
}

function useSubmit(onDone: () => void) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const run = (fn: () => Promise<{ ok: boolean; error?: string; notice?: string }>) =>
    start(async () => {
      const r = await fn();
      if (!r.ok) return setError(r.error ?? "That did not work.");
      if (r.notice) toast.success(r.notice);
      onDone();
      router.refresh();
    });
  return { busy, error, run };
}

function AppSheet({ leadId, app, programme, university, onClose }: { leadId: number; app?: Application; programme: string | null; university: string | null; onClose: () => void }) {
  const { busy, error, run } = useSubmit(onClose);
  return (
    <Sheet title={app ? "Edit application" : "Add an application"} onClose={onClose}>
      <form className="stack" action={(f) => run(() => applicationSave({
        lead_id: leadId, id: app?.id ?? null, university: f.get("university"), programme: f.get("programme"), application_ref: f.get("application_ref"),
        status: f.get("status"), fee_amount: f.get("fee_amount"), fee_paid: f.get("fee_paid"),
      }))}>
        <label className="field"><span>University</span><input className="input" name="university" required defaultValue={app?.university ?? university ?? ""} /></label>
        <label className="field"><span>Programme</span><input className="input" name="programme" required defaultValue={app?.programme ?? programme ?? ""} /></label>
        <label className="field"><span>University&apos;s application ID</span><input className="input" name="application_ref" defaultValue={app?.application_ref ?? ""} /></label>
        <label className="field"><span>Status</span><select className="input" name="status" defaultValue={app?.status ?? "started"}>
          {Object.entries(APP_STATUS_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select></label>
        <div className="grid g2" style={{ gap: 10 }}>
          <label className="field"><span>Programme fee (₹)</span><input className="input" name="fee_amount" type="number" min={0} defaultValue={app?.fee_amount ?? ""} /></label>
          <label className="field"><span>Paid so far (₹)</span><input className="input" name="fee_paid" type="number" min={0} defaultValue={app?.fee_paid ?? ""} /></label>
        </div>
        {error && <p className="error" role="alert">{error}</p>}
        <button className="btn primary block" type="submit" disabled={busy}>{busy ? "Saving…" : "Save application"}</button>
      </form>
    </Sheet>
  );
}

function DocSheet({ leadId, app, item, onClose }: { leadId: number; app: Application; item?: string; onClose: () => void }) {
  const { busy, error, run } = useSubmit(onClose);
  return (
    <Sheet title={`Upload: ${item ?? "a document"}`} onClose={onClose}>
      <form className="stack" action={(f) => run(() => documentAdd(f))}>
        <input type="hidden" name="lead_id" value={leadId} />
        <input type="hidden" name="application_id" value={app.id} />
        <label className="field"><span>Document</span><input className="input" name="kind" defaultValue={item ?? ""} required maxLength={80} /></label>
        <label className="field"><span>File (PDF or photo, up to 4 MB)</span><input className="input" name="file" type="file" accept="application/pdf,image/jpeg,image/png,image/webp" capture="environment" required /></label>
        {error && <p className="error" role="alert">{error}</p>}
        <button className="btn primary block" type="submit" disabled={busy}>{busy ? "Uploading…" : "Upload"}</button>
      </form>
    </Sheet>
  );
}

function EnrolSheet({ leadId, app, programme, university, onClose }: { leadId: number; app?: Application; programme: string | null; university: string | null; onClose: () => void }) {
  const { busy, error, run } = useSubmit(onClose);
  return (
    <Sheet title="Record enrolment" onClose={onClose}>
      <form className="stack" action={(f) => run(() => enrollmentRecord(f))}>
        <input type="hidden" name="lead_id" value={leadId} />
        {app && <input type="hidden" name="application_id" value={app.id} />}
        <label className="field"><span>University</span><input className="input" name="university" required defaultValue={app?.university ?? university ?? ""} /></label>
        <label className="field"><span>Programme</span><input className="input" name="programme" required defaultValue={app?.programme ?? programme ?? ""} /></label>
        <div className="grid g2" style={{ gap: 10 }}>
          <label className="field"><span>Programme fee (₹, required)</span><input className="input" name="fee" type="number" min={1} required defaultValue={app?.fee_amount ?? ""} /></label>
          <label className="field"><span>Paid (₹)</span><input className="input" name="fee_paid" type="number" min={0} defaultValue={app?.fee_paid ?? ""} /></label>
        </div>
        <label className="field"><span>Enrolment date</span><input className="input" name="enrolled_on" type="date" required max={istDay(new Date())} /></label>
        <label className="field"><span>Proof (fee receipt or university letter, required)</span><input className="input" name="proof" type="file" accept="application/pdf,image/jpeg,image/png,image/webp" required /></label>
        <label className="field"><span>Note</span><input className="input" name="note" maxLength={300} /></label>
        {error && <p className="error" role="alert">{error}</p>}
        <button className="btn primary block" type="submit" disabled={busy}>{busy ? "Saving…" : "Record enrolment"}</button>
        <p className="note">The Admin verifies the proof before the enrolment counts for your commission.</p>
      </form>
    </Sheet>
  );
}
