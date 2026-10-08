"use client";
import { useEffect, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { ArrowRightLeft, CheckCheck, FlaskConical, MessageSquareReply, Pencil, Plus, Send, ShieldCheck, ShieldOff, UserX, Waypoints, X } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { cn } from "@/components/ui/cn";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { field, Label, Modal } from "@/components/ui/Modal";
import { friendlyRouteError, LOST_SUCCESS_TOAST, lostDialogCopy, type ConsentPanel, type RoutingActionState } from "@/lib/lead-routing-ui";
import { LANE_LABEL, OUTCOME_LABEL, reasonLabel, type Interest } from "@/lib/routing";
import { markPartnerLost, routeToPartners } from "../routing/actions";
import { consentRecord, consentRequest, interestsSave, reenquiryAck, rerouteLead, routeTestLead, type ConsentAnswerResult, type InterestInput } from "./actions";
import { PassToCrmDialog } from "./PassToCrm";

const area = "w-full resize-none rounded-lg border border-border bg-surface px-3 py-2 text-[13px] text-fg placeholder:text-subtle focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30";

/** The drawer's routing actions (Addendum 3). Which buttons appear, and why one is disabled, comes from
 *  routingActionState() in lib/lead-routing-ui.ts: 'Pass to CRM' for a not-passed lead; 'Send to partners' for a B2C-held
 *  lead, hidden for a partner-barred one (PART 6.3); 'Re-route' as reroute_check allows it (PART 6.2); 'Partner reported
 *  lost' for a pushed or accepted allocation (PART 6.1); the sandbox and B2C test hand-off for test leads (R1). */
export function RoutingActions({ leadId, state: s }: { leadId: number; state: RoutingActionState }) {
  const router = useRouter();
  const [dialog, setDialog] = useState<"pass" | "partners" | "reroute" | "lost" | "sandbox" | "b2c_test" | null>(null);
  const close = () => setDialog(null);
  const done = () => router.refresh();
  const anything = s.passToCrm || s.sendToPartners.show || s.reroute.show || s.lost.show || s.test.sandbox || s.test.b2cTest || s.barred;
  if (!anything) return null;
  const partner = s.lost.partner ?? s.reroute.partner;

  return (
    <div className="flex flex-wrap items-center gap-2">
      {s.passToCrm && <Button size="sm" onClick={() => setDialog("pass")}><Send className="size-3.5" /> Pass to CRM</Button>}
      {s.sendToPartners.show && (
        <Button size="sm" variant="secondary" onClick={() => setDialog("partners")} disabled={Boolean(s.sendToPartners.disabledWhy)} title={s.sendToPartners.disabledWhy ?? undefined}>
          <Waypoints className="size-3.5" /> Send to partners
        </Button>
      )}
      {s.barred && (
        <span className="inline-flex items-center gap-1.5 text-[12.5px] text-danger"><ShieldOff className="size-3.5 shrink-0" /> {s.barredNote}</span>
      )}
      {s.reroute.show && (
        <>
          <Button size="sm" variant="secondary" onClick={() => setDialog("reroute")} disabled={!s.reroute.enabled} title={s.reroute.why ?? undefined}>
            <ArrowRightLeft className="size-3.5" /> Re-route
          </Button>
          {s.reroute.why && <span className={cn("text-[12px]", s.reroute.enabled ? "text-muted" : "text-warning")}>{s.reroute.why}</span>}
        </>
      )}
      {s.lost.show && <Button size="sm" variant="ghost" onClick={() => setDialog("lost")}><UserX className="size-3.5" /> Partner reported lost</Button>}
      {s.test.sandbox && <Button size="sm" variant="secondary" onClick={() => setDialog("sandbox")}><FlaskConical className="size-3.5" /> Route to a partner sandbox</Button>}
      {s.test.b2cTest && <Button size="sm" variant="secondary" onClick={() => setDialog("b2c_test")}><FlaskConical className="size-3.5" /> Send a test hand-off to B2C</Button>}

      <PassToCrmDialog ids={[leadId]} open={dialog === "pass"} onClose={close} onDone={done} />

      <ConfirmDialog
        open={dialog === "partners"}
        onClose={close}
        title="Send this lead to partners?"
        confirmLabel="Send to partners"
        reason={{ label: "Reason for the audit log", placeholder: "e.g. student wants a university only partners offer" }}
        onConfirm={async (reason) => {
          const r = await routeToPartners(leadId, reason);
          if (!r.ok) return friendlyRouteError(r.error);
          const d = r.decision;
          if (d.destination === "partner") toast.success(`Routed to ${d.partner_name ?? "a partner"}${d.reference ? ` (${d.reference})` : ""}`);
          else if (d.destination === "in_house") toast.warning(`No partner could take it; it went back to B2C sales (${reasonLabel(d.reason, d.cause)}).`);
          else toast.warning(OUTCOME_LABEL[d.outcome ?? ""] ?? `Not routed: ${reasonLabel(d.reason, d.cause)}`);
          done();
        }}
      >
        The B2C hold is closed and the lead goes through partner routing by hand: the student must have consented to sharing, and the lead
        must not be partner-barred. If no partner can take it, it returns to its B2C counsellor with the reason
        &quot;sent to partners by hand, none could take it&quot;. Should this manual route end in a duplicate or a loss, the lead becomes partner-barred.
      </ConfirmDialog>

      <RerouteDialog leadId={leadId} open={dialog === "reroute"} onClose={close} partner={s.reroute.partner} barred={s.barred} onDone={done} />

      <ConfirmDialog
        open={dialog === "lost"}
        onClose={close}
        tone="danger"
        title={`${partner ?? "The partner"} marked this lead lost?`}
        confirmLabel="Record: lost, in grace"
        reason={{ label: "What the partner reported", placeholder: "e.g. not interested, joined elsewhere" }}
        onConfirm={async (reason) => {
          if (!s.lost.allocationId) return "No open partner allocation.";
          const err = await markPartnerLost(s.lost.allocationId, reason);
          if (err) return err;
          toast.success(LOST_SUCCESS_TOAST);
          done();
        }}
      >
        {lostDialogCopy(partner)} The lost reason sets when B2C&apos;s first nurture message goes out. Partner sync records this automatically for
        connected CRMs; use this only for a partner that reported by phone or email.
      </ConfirmDialog>

      <ConfirmDialog
        open={dialog === "sandbox"}
        onClose={close}
        title="Route this test lead to a partner sandbox?"
        confirmLabel="Route to sandbox"
        reason={{ label: "Reason (what you are testing)", placeholder: "e.g. LeadSquared adapter, duplicate handling" }}
        onConfirm={async (reason) => {
          const r = await routeTestLead(leadId, "partner_sandbox", reason);
          if (!r.ok) return r.error;
          if (r.destination === "partner") toast.success(`Pushed to ${r.partner_name ?? "a partner"}'s sandbox${r.reference ? ` (${r.reference})` : ""}`);
          else if (r.reason === "no_sandbox_partner") toast.warning("No partner has a sandbox endpoint for this programme; nothing was written.");
          else toast.warning(`Not routed: ${reasonLabel(r.reason, r.cause)}`);
          done();
        }}
      >
        A test allocation goes through the normal partner scoring but is pushed only to a partner with a test endpoint. It is never counted,
        never messages the student and never feeds the statistics (R1).
      </ConfirmDialog>

      <ConfirmDialog
        open={dialog === "b2c_test"}
        onClose={close}
        title="Send a test hand-off to B2C?"
        confirmLabel="Send test hand-off"
        reason={{ label: "Reason (what you are testing)", placeholder: "e.g. B2C CRM contract version 3" }}
        onConfirm={async (reason) => {
          const r = await routeTestLead(leadId, "b2c_test", reason);
          if (!r.ok) return r.error;
          toast.success(`Test hand-off sent to B2C${r.reference ? ` (${r.reference})` : ""}`);
          done();
        }}
      >
        A test allocation with reason &quot;test hand-off&quot; and a b2c.lead_handed_off event flagged test, for B2C integration testing.
        Nothing is counted and the student is not messaged.
      </ConfirmDialog>
    </div>
  );
}

const radio = (active: boolean, disabled = false) => cn(
  "flex cursor-pointer items-start gap-2.5 rounded-lg border px-3 py-2 text-[13px] transition-colors",
  active ? "border-ring bg-amber/10" : "border-border hover:bg-surface-hover",
  disabled && "cursor-not-allowed opacity-50",
);

/** PART 6.2 / D20: recall the partner allocation and hand the lead to a B2C lane or the next-best partner, with a reason. */
function RerouteDialog({ leadId, open, onClose, partner, barred, onDone }: {
  leadId: number; open: boolean; onClose: () => void; partner: string | null; barred: boolean; onDone: () => void;
}) {
  const [to, setTo] = useState<"sales" | "nurture" | "partners">("sales");
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  useEffect(() => { if (open) { setTo("sales"); setReason(""); setError(null); } }, [open]);

  const submit = () => {
    if (reason.trim().length < 3) { setError("Give a reason of 3 to 300 characters."); return; }
    start(async () => {
      const r = to === "partners" ? await rerouteLead(leadId, "partners", reason) : await rerouteLead(leadId, "b2c", reason, to);
      if (!r.ok) { setError(r.error); return; }
      const from = partner ?? "the partner";
      if (r.to === "b2c") toast.success(`Recalled from ${from}; handed to ${LANE_LABEL[to] ?? "B2C"}${r.reference ? ` (${r.reference})` : ""}`);
      else if (r.destination === "partner") toast.success(`Recalled from ${from}; routed to ${r.route?.partner_name ?? "the next-best partner"}${r.reference ? ` (${r.reference})` : ""}`);
      else toast.warning(`Recalled from ${from}; no other partner could take it, so it went to B2C sales (${reasonLabel(r.reason, r.route?.cause)}).`);
      onDone();
      onClose();
    });
  };

  return (
    <Modal open={open} onClose={onClose} title={`Re-route this lead away from ${partner ?? "the partner"}?`} error={error} pending={pending} onSubmit={submit} submitLabel="Re-route">
      <p className="text-[13px] leading-5 text-muted">
        The partner allocation is recalled (its SLAs voided, its pending student messages cancelled) and the partner is told. A re-route to B2C
        never bars the lead; only a duplicate or a loss does.
      </p>
      <fieldset className="space-y-2">
        <legend className="mb-1 text-[13px] font-medium">Where to</legend>
        {([
          ["sales", "B2C sales", "A counsellor of their choice sells it (reason: manual)."],
          ["nurture", "B2C nurture", "Kept warm by B2C; it can be sent to partners by hand later."],
          ["partners", "Another partner", barred ? "Not possible: this lead is partner-barred for ever." : `The next-best partner; ${partner ?? "the recalled partner"} is excluded. The student must have consented to sharing.`],
        ] as const).map(([value, title, hint]) => {
          const disabled = value === "partners" && barred;
          return (
            <label key={value} className={radio(to === value, disabled)}>
              <input type="radio" name="reroute_to" value={value} checked={to === value} disabled={disabled} onChange={() => setTo(value)} className="mt-0.5 accent-[var(--primary)]" />
              <span><span className="font-medium text-fg">{title}</span><span className="block text-[12px] text-muted">{hint}</span></span>
            </label>
          );
        })}
      </fieldset>
      <Label text="Reason (kept with the recall and sent to the partner)">
        <textarea value={reason} onChange={(e) => setReason(e.target.value)} rows={3} maxLength={300} placeholder="e.g. no contact attempt in 3 days; student asked for a different counsellor" className={area} />
      </Label>
    </Modal>
  );
}

// ---------- consent (PART 7, D7, D9) ----------

const effectText = (r: ConsentAnswerResult) => {
  switch (r.effect) {
    case "routed": return "; the lead was routed";
    case "requalified": return "; the lead was requalified and routed";
    case "route_error": return `; routing failed${r.why ? `: ${r.why}` : ""}`;
    default: return "";
  }
};

/** Ask for consent, record a refusal, record a YES given on a call (only with engine.consent_admin_yes and written evidence). */
export function ConsentActions({ leadId, panel }: { leadId: number; panel: ConsentPanel }) {
  const router = useRouter();
  const [dialog, setDialog] = useState<"ask" | "no" | "yes" | null>(null);
  const close = () => setDialog(null);
  return (
    <div className="flex flex-wrap gap-2">
      <Button size="sm" variant="secondary" onClick={() => setDialog("ask")} disabled={!panel.canAsk} title={panel.askWhy ?? undefined}>
        <MessageSquareReply className="size-3.5" /> Ask for consent
      </Button>
      <Button size="sm" variant="ghost" onClick={() => setDialog("no")} disabled={!panel.canRecordNo} title={panel.noWhy ?? undefined}>
        <ShieldOff className="size-3.5" /> Record refusal
      </Button>
      <Button size="sm" variant="ghost" onClick={() => setDialog("yes")} disabled={!panel.canRecordYes} title={panel.yesWhy ?? undefined}>
        <ShieldCheck className="size-3.5" /> Record consent
      </Button>

      <ConfirmDialog
        open={dialog === "ask"}
        onClose={close}
        title="Ask the student for partner-sharing consent?"
        confirmLabel="Send the request"
        reason={{ label: "Reason for the audit log", placeholder: "e.g. student asked to be connected with a counsellor" }}
        onConfirm={async (reason) => {
          const r = await consentRequest(leadId, reason);
          if (!r.ok) return r.error;
          const from = r.channel === "witty" ? "Witty's number" : "the B2C number";
          if (r.created) {
            if (r.status === "queued") toast.success(`Consent request queued for ${from} (over the hourly budget; it goes out when the budget allows)`);
            else if (r.status === "unsendable") toast.warning("Consent request recorded, but it could not be sent: no B2C endpoint subscribes to consent requests.");
            else toast.success(`Consent requested from ${from}${r.programme ? ` for ${r.programme}` : ""}`);
          } else if (r.existing) toast.warning("A consent request is already open for this lead.");
          else toast.warning(r.why ? r.why.charAt(0).toUpperCase() + r.why.slice(1) : "No request was created.");
          router.refresh();
        }}
      >
        One WhatsApp message asks: &quot;To connect you with the best admission counsellor for {"{{programme}}"}, may we share your details with our
        admission partner? Reply YES or NO.&quot; It goes from Witty&apos;s number when the lead came through Witty (and Witty can send it), otherwise from
        the B2C number. YES routes the lead to partners; NO keeps it with B2C sales; no answer in 48 hours keeps it in B2C nurture.
      </ConfirmDialog>

      <ConsentRecordDialog leadId={leadId} answer="no" open={dialog === "no"} onClose={close} onDone={() => router.refresh()} />
      <ConsentRecordDialog leadId={leadId} answer="yes" open={dialog === "yes"} onClose={close} onDone={() => router.refresh()} />
    </div>
  );
}

function ConsentRecordDialog({ leadId, answer, open, onClose, onDone }: { leadId: number; answer: "yes" | "no"; open: boolean; onClose: () => void; onDone: () => void }) {
  const [note, setNote] = useState("");
  const [evidence, setEvidence] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  useEffect(() => { if (open) { setNote(""); setEvidence(""); setError(null); } }, [open]);
  const yes = answer === "yes";

  const submit = () => {
    if (note.trim().length < 10) { setError("Write a note of 10 to 300 characters: what the student said, when and to whom."); return; }
    if (yes && !evidence.trim()) { setError("A written evidence reference is required for a YES (a message, recording or ticket reference)."); return; }
    start(async () => {
      const r = await consentRecord(leadId, answer, note, yes ? evidence : null);
      if (!r.ok) { setError(r.error); return; }
      if (r.duplicate) toast.warning("This answer was already recorded.");
      else toast.success(`${yes ? "Consent" : "Refusal"} recorded${effectText(r)}`);
      onDone();
      onClose();
    });
  };

  return (
    <Modal open={open} onClose={onClose} title={yes ? "Record partner-sharing consent given to you?" : "Record that the student said NO?"} error={error} pending={pending} onSubmit={submit}
      submitLabel={yes ? "Record consent" : "Record refusal"}>
      <p className="text-[13px] leading-5 text-muted">
        {yes
          ? "Only for a YES the student gave on a call or in writing to Eduwit. It is written to the consent ledger with your name, and the lead is then routed (or requalified) if it was waiting for consent."
          : "A refusal keeps the lead with B2C (reason: student said NO to sharing). It can always be recorded; a later YES from the student overrides it."}
      </p>
      <Label text="Note (10 characters or more)">
        <textarea value={note} onChange={(e) => setNote(e.target.value)} rows={3} maxLength={300} className={area}
          placeholder={yes ? "e.g. said yes on the call of 8 Oct 11:20 with Priya" : "e.g. does not want their number shared; call of 8 Oct"} />
      </Label>
      {yes && (
        <Label text="Evidence reference" hint="Where the written evidence is: a WhatsApp message ID, a call recording ID, a ticket number.">
          <input value={evidence} onChange={(e) => setEvidence(e.target.value)} maxLength={300} className={field} placeholder="e.g. Exotel recording 8821-… / ticket #412" />
        </Label>
      )}
    </Modal>
  );
}

// ---------- re-enquiries (D18) ----------

/** Acknowledge the open re-enquiries of a held lead (they are recorded, never re-routed); the note is optional. */
export function AcknowledgeButton({ ids }: { ids: number[] }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [note, setNote] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  useEffect(() => { if (open) { setNote(""); setError(null); } }, [open]);
  if (ids.length === 0) return null;
  const submit = () => start(async () => {
    const r = await reenquiryAck(ids, note);
    if (!r.ok) { setError(r.error); return; }
    toast.success(`Acknowledged ${r.count} ${r.count === 1 ? "re-enquiry" : "re-enquiries"}`);
    router.refresh();
    setOpen(false);
  });
  return (
    <>
      <Button size="sm" variant="secondary" onClick={() => setOpen(true)}><CheckCheck className="size-3.5" /> Acknowledge{ids.length > 1 ? ` (${ids.length})` : ""}</Button>
      <Modal open={open} onClose={() => setOpen(false)} title={ids.length === 1 ? "Acknowledge this re-enquiry?" : `Acknowledge ${ids.length} re-enquiries?`} error={error} pending={pending} onSubmit={submit} submitLabel="Acknowledge">
        <p className="text-[13px] leading-5 text-muted">
          The student enquired again while the lead was held. Re-enquiries are recorded on the lead and never re-routed (R2–R4); acknowledging
          clears them from the Re-enquired view.
        </p>
        <Label text="Note (optional)">
          <textarea value={note} onChange={(e) => setNote(e.target.value)} rows={2} maxLength={300} className={area} placeholder="e.g. told the partner; counsellor will call back" />
        </Label>
      </Modal>
    </>
  );
}

// ---------- other interests (D30) ----------

const LEVELS = ["UG", "PG", "DIPLOMA", "CERTIFICATE"] as const;
const MODES = ["Online", "ODL", "Regular"] as const;
const blank = (): InterestInput => ({ course: "", specialization: "", level: null, mode: null, university: "" });
const fromInterest = (i: Interest): InterestInput => ({
  course: i.course_text ?? i.course_key ?? "", specialization: i.specialization ?? "",
  level: LEVELS.includes(i.level as (typeof LEVELS)[number]) ? i.level : null, mode: MODES.includes(i.mode as (typeof MODES)[number]) ? i.mode : null,
  university: i.university_text ?? "",
});

/** Edit the student's other interests (secondary interests, positions 2–10). The engine tries them in order when no partner
 *  offers the primary one (PART 4, D30). */
export function InterestsEditor({ leadId, interests }: { leadId: number; interests: Interest[] }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [rows, setRows] = useState<InterestInput[]>([]);
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const secondary = interests.filter((i) => (i.rank ?? 1) > 1);
  const openEditor = () => { setRows(secondary.length ? secondary.map(fromInterest) : [blank()]); setReason(""); setError(null); setOpen(true); };

  const set = (i: number, patch: Partial<InterestInput>) => setRows((rs) => rs.map((r, k) => (k === i ? { ...r, ...patch } : r)));
  const submit = () => {
    const list = rows.filter((r) => r.course.trim());
    if (reason.trim().length < 3) { setError("Give a reason of 3 to 300 characters."); return; }
    start(async () => {
      const r = await interestsSave(leadId, list.map((x) => ({ ...x, specialization: x.specialization || null, university: x.university || null })), reason);
      if (!r.ok) { setError(r.error); return; }
      const n = r.interests.filter((i) => (i.rank ?? 1) > 1).length;
      toast.success(n === 0 ? "No other interests" : `Saved ${n} other ${n === 1 ? "interest" : "interests"}`);
      router.refresh();
      setOpen(false);
    });
  };

  return (
    <>
      <Button size="sm" variant="ghost" onClick={openEditor}><Pencil className="size-3.5" /> {secondary.length ? "Edit" : "Add other interests"}</Button>
      <Modal open={open} onClose={() => setOpen(false)} title="Other interests" error={error} pending={pending} onSubmit={submit} submitLabel="Save interests" wide>
        <p className="text-[13px] leading-5 text-muted">
          When no live partner offers the student&apos;s first choice, the engine tries these in order (up to the Admin&apos;s limit). The first
          choice itself is edited on the Edit tab. Rows without a course are dropped.
        </p>
        <div className="space-y-2">
          {rows.map((r, i) => (
            <div key={i} className="grid grid-cols-[1fr_auto] gap-2 rounded-lg border border-border p-2.5 sm:grid-cols-[2fr_2fr_1fr_1fr_2fr_auto]">
              <input value={r.course} onChange={(e) => set(i, { course: e.target.value })} maxLength={120} placeholder={`Course ${i + 2}`} className={field} aria-label={`Course ${i + 2}`} />
              <input value={r.specialization ?? ""} onChange={(e) => set(i, { specialization: e.target.value })} maxLength={120} placeholder="Specialisation" className={cn(field, "col-start-1 sm:col-start-auto")} aria-label="Specialisation" />
              <select value={r.level ?? ""} onChange={(e) => set(i, { level: e.target.value || null })} className={cn(field, "col-start-1 sm:col-start-auto")} aria-label="Level">
                <option value="">Level</option>
                {LEVELS.map((l) => <option key={l} value={l}>{l}</option>)}
              </select>
              <select value={r.mode ?? ""} onChange={(e) => set(i, { mode: e.target.value || null })} className={cn(field, "col-start-1 sm:col-start-auto")} aria-label="Study mode">
                <option value="">Mode</option>
                {MODES.map((m) => <option key={m} value={m}>{m}</option>)}
              </select>
              <input value={r.university ?? ""} onChange={(e) => set(i, { university: e.target.value })} maxLength={160} placeholder="University (optional)" className={cn(field, "col-start-1 sm:col-start-auto")} aria-label="University" />
              <Button type="button" variant="ghost" size="icon" className="col-start-2 row-start-1 h-9 w-9 self-start sm:col-start-auto sm:row-start-auto" onClick={() => setRows((rs) => rs.filter((_, k) => k !== i))} aria-label="Remove this interest">
                <X className="size-4" />
              </Button>
            </div>
          ))}
          {rows.length < 9 && (
            <Button type="button" variant="secondary" size="sm" onClick={() => setRows((rs) => [...rs, blank()])}><Plus className="size-3.5" /> Add an interest</Button>
          )}
        </div>
        <Label text="Reason (kept with the change)">
          <input value={reason} onChange={(e) => setReason(e.target.value)} maxLength={300} className={field} placeholder="e.g. student mentioned an MCA as an alternative on the call" />
        </Label>
      </Modal>
    </>
  );
}
