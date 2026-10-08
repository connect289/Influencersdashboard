"use client";
import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { LoaderCircle, Plus, ShieldCheck } from "lucide-react";
import { toast } from "sonner";
import { Badge, EmptyState } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { Notice } from "@/components/ui/Notice";
import { cn } from "@/components/ui/cn";
import { formatDateTime, relativeTime } from "@/lib/format";
import {
  CONSENT_CHANNELS, CONSENT_CHANNEL_LABEL, CONSENT_PURPOSES, CONSENT_PURPOSE_LABEL, consentGolive, consentTextProblems, textCovers,
  type ConsentText, type ConsentTextForm,
} from "@/lib/intake";
import { saveConsentText } from "./actions";
import { area, field, label } from "./ui";

const EXAMPLE = "I agree that Eduwit and its admission partners (edtech companies) may contact me on WhatsApp, phone and email about the courses I asked about.";

const blank = (): ConsentTextForm => ({ version: "", channel: "web_form", purposes: ["sales", "partner_share"], body: "", covers_admission_partners: true, active: true, approval_note: "" });

const fromRow = (t: ConsentText): ConsentTextForm => ({
  version: t.version, channel: t.channel, purposes: t.purposes, body: t.body ?? "", covers_admission_partners: t.covers_admission_partners, active: t.active,
  approval_note: t.approval_note ?? "",
});

/**
 * One consent text: the wording a channel shows, which purposes it covers, whether it names the admission partners and the
 * lawyer's approval. Writes through b2b.consent_text_save (the function re-checks everything and keeps the audit event).
 */
function TextDialog({ open, stored, onClose }: { open: boolean; stored: ConsentText | null; onClose: () => void }) {
  const ref = useRef<HTMLDialogElement>(null);
  const [f, setF] = useState<ConsentTextForm>(blank());
  const [approved, setApproved] = useState(false);
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const editing = Boolean(stored);
  const wasApproved = Boolean(stored?.lawyer_approved_at);

  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) {
      setF(stored ? fromRow(stored) : blank()); setApproved(Boolean(stored?.lawyer_approved_at)); setReason(""); setError(null); d.showModal();
    }
    if (!open && d.open) d.close();
  }, [open, stored]);

  const wordingChanged = wasApproved && ((stored?.body ?? "") !== f.body.trim() || Boolean(stored?.covers_admission_partners) !== f.covers_admission_partners);
  // what the save says about the approval: true approves (again, after a wording change), false clears, undefined leaves it as
  // stored (consent_text_save then still takes a changed note)
  const lawyer_approved = approved ? (!wasApproved || wordingChanged ? true : undefined) : wasApproved ? false : undefined;
  const payload: ConsentTextForm = { ...f, lawyer_approved };
  const check = consentTextProblems(payload, stored);
  const canSave = check.errors.length === 0 && reason.trim().length >= 3 && !pending;

  // a changed wording is no longer the one the lawyer checked: the box unticks itself and must be ticked again
  const setWording = (patch: Partial<Pick<ConsentTextForm, "body" | "covers_admission_partners">>) => {
    const next = { ...f, ...patch };
    setF(next);
    if (wasApproved && approved && ((stored?.body ?? "") !== next.body.trim() || Boolean(stored?.covers_admission_partners) !== next.covers_admission_partners)) setApproved(false);
  };

  const save = async () => {
    setPending(true); setError(null);
    try {
      const r = await saveConsentText(payload, reason);
      if (!r.ok) { setError(r.error); return; }
      toast.success(r.data.lawyer_approved_at ? `${r.data.version} saved and approved` : `${r.data.version} saved`);
      onClose();
    } finally { setPending(false); }
  };

  return (
    <dialog ref={ref} onClose={onClose} aria-labelledby="consent-text-title"
      className="m-auto w-[min(720px,calc(100vw-2rem))] rounded-[var(--radius-card)] border border-border bg-surface p-0 text-fg shadow-2xl backdrop:bg-overlay backdrop:backdrop-blur-sm">
      <div className="max-h-[78vh] space-y-4 overflow-y-auto p-5">
        <div>
          <h2 id="consent-text-title" className="text-[15px] font-semibold">{editing ? <>Consent text <span className="font-mono">{stored?.version}</span></> : "Register a consent text"}</h2>
          <p className="mt-0.5 text-[12.5px] text-muted">The exact wording a channel shows, so every consent stamp can be traced to it (consent_text_version). Register each channel&apos;s line once per version; edit the text here when the wording changes.</p>
        </div>
        <div className="grid gap-3 sm:grid-cols-2">
          <label className="block space-y-1"><span className={label}>Version id</span>
            <input className={`${field} font-mono`} value={f.version} disabled={editing} maxLength={80} placeholder="e.g. web-form-2026-10" onChange={(e) => setF({ ...f, version: e.target.value })} />
            {!editing && <span className="text-xs text-muted">Short and unique; it is written on every lead that agrees to this text.</span>}</label>
          <label className="block space-y-1"><span className={label}>Shown on</span>
            <select className={field} value={f.channel} onChange={(e) => setF({ ...f, channel: e.target.value as ConsentTextForm["channel"] })}>
              {CONSENT_CHANNELS.map((c) => <option key={c.key} value={c.key}>{c.label}</option>)}
            </select></label>
        </div>
        <fieldset className="space-y-1.5">
          <legend className={label}>What the student agrees to</legend>
          <div className="flex flex-wrap gap-x-5 gap-y-1.5 text-[13px]">
            {CONSENT_PURPOSES.map((p) => (
              <label key={p} className="flex items-center gap-2"><input type="checkbox" className="accent-[var(--primary)]" checked={f.purposes.includes(p)}
                onChange={(e) => setF({ ...f, purposes: e.target.checked ? [...f.purposes, p] : f.purposes.filter((x) => x !== p) })} />{CONSENT_PURPOSE_LABEL[p]}</label>
            ))}
          </div>
        </fieldset>
        <label className="block space-y-1"><span className={label}>The wording</span>
          <textarea className={`${area} min-h-28`} value={f.body} maxLength={4000} placeholder={`e.g. ${EXAMPLE}`} onChange={(e) => setWording({ body: e.target.value })} />
          <span className="text-xs text-muted">PART 7.1: it must cover sharing with &quot;our admission partners (edtech companies)&quot;, not only universities.</span></label>
        <div className="space-y-1.5 text-[13px]">
          <label className="flex items-start gap-2"><input type="checkbox" className="mt-0.5 accent-[var(--primary)]" checked={f.covers_admission_partners} onChange={(e) => setWording({ covers_admission_partners: e.target.checked })} />
            <span><span className="font-medium text-fg">This wording names our admission partners (edtech companies)</span>
              <span className="block text-[12.5px] text-muted">Only a text with this tick makes a partner-sharing stamp count; forms and manual entry can choose it for partner sharing.</span></span></label>
          <label className="flex items-center gap-2"><input type="checkbox" className="accent-[var(--primary)]" checked={f.active} onChange={(e) => setF({ ...f, active: e.target.checked })} />
            <span className="font-medium text-fg">Active</span><span className="text-[12.5px] text-muted">— switch off a text no channel shows any more; its old stamps stay valid.</span></label>
        </div>

        <fieldset className="space-y-2 rounded-lg border border-border p-3">
          <legend className="flex items-center gap-1.5 px-1 text-[13px] font-semibold text-fg"><ShieldCheck className="size-3.5 text-muted" /> Lawyer&apos;s approval</legend>
          <p className="text-[12.5px] text-muted">Routing cannot go live while an active text that covers admission partners is unapproved (go-live checklist). Record here who checked the wording and when.</p>
          {wasApproved && !wordingChanged && (
            <p className="text-[12.5px] text-muted">Approved by <span className="text-fg">{stored?.approved_by ?? "—"}</span> on {formatDateTime(stored?.lawyer_approved_at)}.</p>
          )}
          <label className="flex items-center gap-2 text-[13px]"><input type="checkbox" className="accent-[var(--primary)]" checked={approved} onChange={(e) => setApproved(e.target.checked)} />
            <span className="font-medium text-fg">Checked and approved by Eduwit&apos;s lawyer</span></label>
          {check.clearsApproval && <Notice tone="warning">The wording changed, so saving clears the lawyer&apos;s approval. Tick the box again once the lawyer has checked the new text.</Notice>}
          {(approved || f.approval_note) && (
            <label className="block space-y-1"><span className={label}>Approval note {approved && <span className="font-normal text-subtle">(at least 10 characters)</span>}</span>
              <textarea className={area} value={f.approval_note} maxLength={1000} placeholder="e.g. Reviewed by Adv. Mehta on 7 Oct 2026, email of the same day" onChange={(e) => setF({ ...f, approval_note: e.target.value })} /></label>
          )}
        </fieldset>

        <label className="block space-y-1"><span className={label}>Reason for this change</span>
          <input className={field} value={reason} maxLength={300} placeholder="e.g. new wording for the October landing pages" onChange={(e) => setReason(e.target.value)} /></label>

        {check.errors.length > 0 && <ul className="list-disc space-y-0.5 pl-5 text-[12.5px] text-danger">{check.errors.map((e) => <li key={e}>{e}</li>)}</ul>}
        {check.warnings.map((w) => <Notice key={w} tone="warning">{w}</Notice>)}
        {error && <p role="alert" className="text-[13px] text-danger">{error}</p>}
      </div>
      <div className="flex justify-end gap-2 border-t border-border bg-surface-2/60 px-5 py-3">
        <Button variant="secondary" size="sm" onClick={onClose} disabled={pending}>Cancel</Button>
        <Button size="sm" onClick={save} disabled={!canSave}>{pending && <LoaderCircle className="size-3.5 animate-spin" />} {lawyer_approved === true ? "Save and approve" : "Save"}</Button>
      </div>
    </dialog>
  );
}

function Approval({ t }: { t: ConsentText }) {
  if (t.lawyer_approved_at) return <Badge tone="success"><span title={`${t.approved_by ?? ""} · ${formatDateTime(t.lawyer_approved_at)}${t.approval_note ? ` · ${t.approval_note}` : ""}`}>Approved {relativeTime(t.lawyer_approved_at)}</span></Badge>;
  if (t.active && t.covers_admission_partners) return <Badge tone="warning">Awaiting the lawyer</Badge>;
  return <Badge>Not approved</Badge>;
}

/** Registered consent texts: which versions cover the admission partners, and the lawyer's approval state (a go-live condition). */
export function ConsentTexts({ texts }: { texts: ConsentText[] }) {
  const [edit, setEdit] = useState<ConsentText | null>(null);
  const [open, setOpen] = useState(false);
  const golive = consentGolive(texts);
  const covering = texts.filter(textCovers).length;

  return (
    <>
      <div className="space-y-3 border-b border-border px-5 py-4">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <p className="max-w-3xl text-[13px] leading-5 text-muted">
            Every consent line a student sees — Witty&apos;s message, the website agent, every website and landing-page form, the Meta and Google disclaimers, the import sheets — must
            cover sharing with <span className="font-medium text-fg">our admission partners (edtech companies)</span>, and the wording must be checked by Eduwit&apos;s lawyer (PART 7.1).
            A partner-sharing consent recorded under a text that does not cover them does not count: those students are asked again with the one-tap WhatsApp request (PART 7.2).
          </p>
          <Button size="sm" onClick={() => { setEdit(null); setOpen(true); }}><Plus className="size-3.5" /> Register a text</Button>
        </div>
        {golive.ok ? (
          <Notice tone="success">{golive.approved} covering {golive.approved === 1 ? "text is" : "texts are"} approved: the consent item of the routing go-live checklist passes.</Notice>
        ) : golive.unapproved.length > 0 ? (
          <Notice tone="warning">Awaiting the lawyer&apos;s approval: <span className="font-mono">{golive.unapproved.join(", ")}</span>. Routing cannot go live until every active covering text is approved — or switched off if no channel shows it.{" "}
            <Link href="/routing" className="font-medium underline">Go-live checklist</Link></Notice>
        ) : (
          <Notice tone="warning">No active text covers admission partners yet. Register the wording each channel shows and tick &quot;names our admission partners&quot;; routing stays off until one is approved.</Notice>
        )}
      </div>
      {texts.length === 0 ? (
        <EmptyState icon={ShieldCheck} title="No consent texts registered">The migration seeds Witty&apos;s notice and the WhatsApp request; website forms, imports and Meta or Google disclaimers are added here.</EmptyState>
      ) : (
        <ul className="divide-y divide-border">
          {texts.map((t) => {
            const covers = textCovers(t);
            return (
              <li key={t.version} className={cn("flex flex-wrap items-start gap-x-4 gap-y-2 px-5 py-3", !t.active && "opacity-70")}>
                <div className="min-w-0 flex-1 basis-[18rem]">
                  <p className="flex flex-wrap items-center gap-x-2 gap-y-1 text-[13.5px]">
                    <span className="font-mono font-medium text-fg">{t.version}</span>
                    <span className="text-[12px] text-subtle">{CONSENT_CHANNEL_LABEL[t.channel] ?? t.channel} · {t.purposes.map((p) => CONSENT_PURPOSE_LABEL[p] ?? p).join(", ")}</span>
                  </p>
                  {t.body ? <p className="mt-0.5 line-clamp-2 text-[12.5px] text-muted" title={t.body}>{t.body}</p> : <p className="mt-0.5 text-[12.5px] italic text-subtle">No wording stored</p>}
                </div>
                <div className="flex flex-wrap gap-1.5">
                  {covers ? <Badge tone="success">Covers admission partners</Badge>
                    : t.purposes.includes("partner_share") ? <Badge tone="warning">Partner sharing does not count</Badge> : <Badge>No partner sharing</Badge>}
                  <Approval t={t} />
                  {!t.active && <Badge>Off</Badge>}
                </div>
                <Button size="sm" variant="secondary" onClick={() => { setEdit(t); setOpen(true); }}>Edit</Button>
              </li>
            );
          })}
        </ul>
      )}
      {texts.length > 0 && <p className="border-t border-border px-5 py-2 text-[12px] text-subtle">{covering} of {texts.length} texts cover admission partners. Texts named import:&lt;id&gt; were registered by the import wizard.</p>}
      <TextDialog open={open} stored={edit} onClose={() => setOpen(false)} />
    </>
  );
}
