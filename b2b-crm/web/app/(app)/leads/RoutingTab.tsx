import Link from "next/link";
import { Ban, CircleCheck, CircleDashed, Clock, Hourglass, ListChecks, Megaphone, MessageSquareReply, Route, ShieldOff, TriangleAlert } from "lucide-react";
import { buttonClass } from "@/components/ui/Button";
import { Badge, EmptyState } from "@/components/ui/Card";
import { formatDateTime, relativeTime } from "@/lib/format";
import {
  allocationStatusText, BARRED_SENTENCE, consentPanel, graceCountdown, holdText, nurtureSummary, ORIGIN_LABEL, outlookText, providersSentence, reenquiriesTitle,
  reenquiryHolderText, routingActionState, waitText,
} from "@/lib/lead-routing-ui";
import { humanize } from "@/lib/leads";
import { CHANNEL_LABEL, STATUS_LABEL as NOTIFY_LABEL, STATUS_TONE as NOTIFY_TONE } from "@/lib/notifications";
import { decisionModeLabel, LANE_LABEL, notPassedLabel, reasonLabel, segmentLabel } from "@/lib/routing";
import type { LeadRouting } from "@/lib/routing-data";
import { createClient } from "@/lib/supabase/server";
import { AcknowledgeButton, ConsentActions, InterestsEditor, RoutingActions } from "./RoutingActions";

/** engine.consent_admin_yes (D9): whether the Admin may record a YES given on a call. Read as the signed-in Admin; false when
 *  the setting cannot be read. */
async function consentAdminYes(): Promise<boolean> {
  try {
    const supabase = await createClient();
    const { data } = await supabase.schema("b2b").from("settings").select("value").eq("key", "engine").maybeSingle();
    return Boolean((data?.value as { consent_admin_yes?: boolean } | null)?.consent_admin_yes);
  } catch {
    return false;
  }
}

function H3({ children }: { children: React.ReactNode }) {
  return <h3 className="mb-2 flex items-center gap-1.5 text-[11px] font-medium uppercase tracking-wider text-subtle">{children}</h3>;
}

const ledgerTone = (state: "given" | "refused" | "withdrawn") => (state === "given" ? "success" : "danger");

/** The lead drawer's Routing tab (Addendum 3): the bar, where the lead is held and where it would go, partner-sharing consent
 *  with its actions, re-enquiries, the qualification nurture, the lost grace, the student's other interests, then every
 *  allocation and decision. The decision logic lives in lib/lead-routing-ui.ts. */
export async function RoutingTab({ leadId, r }: { leadId: number; r: LeadRouting | null }) {
  if (!r) return <EmptyState icon={Route} title="Routing is not available">The routing details could not be loaded.</EmptyState>;
  const adminYes = await consentAdminYes();
  const now = Date.now();
  const actions = routingActionState(r);
  const consent = consentPanel(r, { adminYes, now });
  const grace = graceCountdown(r, now);
  const nurture = nurtureSummary(r);
  const wait = waitText(r);
  const hold = holdText(r);
  const np = r.not_passed && !r.not_passed.passed_at ? r.not_passed : null;
  const flag = r.flags.find((f) => !f.resolved_at);
  const cls = r.readiness.class;
  const openReenquiries = r.reenquiries.filter((q) => !q.acknowledged_at);
  const secondary = r.interests.filter((i) => (i.rank ?? 1) > 1);
  const ledgerShown = consent.ledger.slice(0, 8);
  // The bar banner names the providers: the proven duplicates of the lead, else the providers recorded with the bar itself.
  const barProviders = r.bar
    ? providersSentence(r.other_providers.length ? r.other_providers : r.bar.providers.map((p) => ({ partner_id: p.partner_id ?? 0, partner_name: p.partner_name ?? null, first_had_at: p.first_had_at ?? null })))
    : null;

  return (
    <div className="divide-y divide-border">
      {np && (
        <section className="flex gap-3 bg-danger-bg/60 px-5 py-3 text-[13px]">
          <ShieldOff className="mt-0.5 size-4 shrink-0 text-danger" />
          <p className="text-fg">
            <span className="font-medium">Not passed to any CRM:</span> {notPassedLabel(np.reason, np.detail)}
            {np.requested_course && <> · asked for {np.requested_course}</>} · <span title={formatDateTime(np.decided_at)}>{relativeTime(np.decided_at)}</span>.
            <span className="block text-[12px] text-muted">It stays in the master database. Pass it to a CRM to have it judged on its details instead; it is also passed at the next hand-off point if Witty classifies it differently.</span>
          </p>
        </section>
      )}
      {flag && (
        <section className="flex gap-3 bg-warning-bg/60 px-5 py-3 text-[13px] text-fg">
          <TriangleAlert className="mt-0.5 size-4 shrink-0 text-warning" />
          <p>Witty now classifies this passed lead {flag.lead_status === "PROGRAM_MISMATCH" ? "programme mismatch" : "junk"}. It is in the review queue on the Routing screen; it is not moved.</p>
        </section>
      )}
      {r.bar && (
        <section className="flex gap-3 bg-danger-bg/60 px-5 py-3 text-[13px]">
          <Ban className="mt-0.5 size-4 shrink-0 text-danger" />
          <div className="min-w-0 text-fg">
            <p>
              <span className="font-medium">Partner-barred for ever</span> · {r.bar.reason === "duplicate" ? "duplicate at partners" : "lost by a partner"} · since{" "}
              <span title={formatDateTime(r.bar.barred_at)}>{formatDateTime(r.bar.barred_at)}</span>
              {r.bar.set_by === "grace" ? " (after the 7-day grace)" : r.bar.set_by === "manual_route" ? " (a manual route ended in a duplicate)" : r.bar.set_by === "backfill" ? " (backfilled)" : ""}
              {r.bar.via !== "lead" && <> · matched through {r.bar.via === "phone" ? "the same phone number" : "a merged lead"}</>}.
            </p>
            <p className="text-[12px] text-muted">
              {BARRED_SENTENCE}: not automatically, not by hand, not in a later enquiry cycle. New enquiries go to B2C as re-enquired.
              {barProviders && <> {barProviders}.</>}
            </p>
          </div>
        </section>
      )}
      {!r.bar && r.other_providers.length > 0 && (
        <section className="flex gap-3 bg-warning-bg/60 px-5 py-3 text-[13px] text-fg">
          <TriangleAlert className="mt-0.5 size-4 shrink-0 text-warning" />
          <p>{providersSentence(r.other_providers)}. <span className="text-muted">These partners proved they already had the student.</span></p>
        </section>
      )}

      <section className="space-y-2 px-5 py-4">
        <div className="flex flex-wrap items-center gap-2">
          {r.readiness.ready
            ? <Badge tone="success"><CircleCheck className="size-3" /> At its decision point</Badge>
            : r.readiness.missing.includes("already routed")
              ? <Badge tone="info"><CircleCheck className="size-3" /> Routed</Badge>
              : <Badge tone="warning"><CircleDashed className="size-3" /> Not ready</Badge>}
          {cls && <Badge tone={cls === "qualified" ? "success" : cls === "unqualified" ? "neutral" : "danger"}>{cls === "qualified" ? "Qualified" : cls === "unqualified" ? "Not qualified" : cls === "junk" ? "Junk" : "Programme mismatch"}</Badge>}
          {(r.attribution?.paid || r.readiness.paid) && <Badge tone="info"><Megaphone className="size-3" /> Paid: {r.attribution?.label ?? r.readiness.paid}</Badge>}
          <Badge tone={consent.tone}>{consent.label}</Badge>
          <Badge>{segmentLabel(r.interest.segment)}</Badge>
          {r.is_test && <Badge tone="brand">Test lead</Badge>}
          {!r.routing_live && <Badge>Automatic routing off</Badge>}
        </div>
        {wait && <p className="text-[12.5px] text-muted"><Clock className="mr-1 inline size-3.5 align-[-2px]" />{wait}.</p>}
        {cls === "unqualified" && !nurture?.active && (r.readiness.not_qualified ?? []).length > 0 && (
          <p className="text-[12.5px] text-muted">Not qualified yet ({(r.readiness.not_qualified ?? []).join(", ")}), so at its decision point it goes to B2C qualification nurture.</p>
        )}
        <dl className="grid grid-cols-[minmax(110px,32%)_1fr] gap-x-4 gap-y-1 text-[13px]">
          {hold && <><dt className="text-muted">Held by</dt><dd className="text-fg">{hold}{r.hold?.lane && r.hold.kind !== "qualification_nurture" ? ` · ${LANE_LABEL[r.hold.lane]}` : ""}</dd></>}
          <dt className="text-muted">{hold || r.readiness.missing.includes("already routed") ? "Next decision would be" : "Would go to"}</dt>
          <dd className="text-fg">{outlookText(r)}</dd>
        </dl>
        <div className="flex flex-wrap gap-2 pt-1">
          <Link href={`/routing?tab=simulate&lead=${leadId}`} className={buttonClass("secondary", "sm")}><Route className="size-3.5" /> Simulate routing</Link>
          <RoutingActions leadId={leadId} state={actions} />
        </div>
      </section>

      <section className="px-5 py-4">
        <H3><MessageSquareReply className="size-3.5" /> Partner-sharing consent</H3>
        <div className="space-y-2 text-[13px]">
          <p className="text-fg">
            <Badge tone={consent.tone}>{consent.label}</Badge>
            {consent.given && (
              <span className="ml-2 text-muted">
                {consent.given.at ? `given ${formatDateTime(consent.given.at)}` : "given"}
                {consent.given.version ? ` · text ${consent.given.version}` : ""}{consent.given.source ? ` · via ${humanize(consent.given.source)}` : ""}
              </span>
            )}
            {!consent.given && consent.refusedAt && <span className="ml-2 text-muted">refused {formatDateTime(consent.refusedAt)}</span>}
          </p>
          {consent.stampUncovered && (
            <p className="text-[12.5px] text-muted">The lead carries a consent stamp whose wording does not name our admission partners (edtech companies), so it does not count (PART 7.1). The student is asked at the decision point.</p>
          )}
          {consent.request && (
            <div className={`rounded-lg border px-3 py-2 ${consent.request.open ? "border-info/25 bg-info-bg/60" : "border-border bg-surface-2/60"}`}>
              <p className="text-fg">
                <span className="font-medium">{consent.request.open ? "Open request" : "Last request"}</span> · {consent.request.statusLabel} · from {consent.request.channelLabel}
                {consent.request.countdown && <> · <span className={consent.request.open && consent.request.countdown !== "queued" ? "tabular" : ""}>{consent.request.countdown}</span></>}
              </p>
              <p className="text-[12px] text-muted">
                {consent.request.programme ? `Names ${consent.request.programme}` : "Programme not named"}
                {consent.request.context ? ` · asked at ${consent.request.context === "decision" ? "the decision point" : consent.request.context === "nurture" ? "requalification" : "the Admin's request"}` : ""}
                {consent.request.createdAt ? ` · ${relativeTime(consent.request.createdAt)}` : ""}
                {consent.request.expiresAt && consent.request.open ? ` · expires ${formatDateTime(consent.request.expiresAt)}` : ""}
                {consent.request.open && consent.request.countdown === "queued" ? " · waits for the hourly request budget; its 48 hours start when it is sent" : ""}
              </p>
            </div>
          )}
          <ConsentActions leadId={leadId} panel={consent} />
          {ledgerShown.length > 0 && (
            <ul className="space-y-1 pt-1">
              {ledgerShown.map((c) => (
                <li key={c.id} className="flex flex-wrap items-center gap-x-2 gap-y-0.5 text-[12.5px]">
                  <Badge tone={ledgerTone(c.state)}>{c.state === "given" ? "Given" : c.state === "refused" ? "Refused" : "Withdrawn"}</Badge>
                  <span className="text-muted">{humanize(c.purpose)}</span>
                  <span className="text-subtle" title={formatDateTime(c.at)}>{relativeTime(c.at)}</span>
                  <span className="text-subtle">· via {humanize(c.source)}{c.text_version ? ` · ${c.text_version}` : ""}</span>
                </li>
              ))}
              {consent.ledger.length > ledgerShown.length && <li className="text-[12px] text-subtle">and {consent.ledger.length - ledgerShown.length} earlier entries</li>}
            </ul>
          )}
        </div>
      </section>

      {r.reenquiries.length > 0 && (
        <section className="px-5 py-4">
          <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
            <H3><TriangleAlert className="size-3.5" /> {reenquiriesTitle(openReenquiries.length ? openReenquiries : r.reenquiries)}{openReenquiries.length > 0 && <Badge tone="warning">{openReenquiries.length} open</Badge>}</H3>
            <AcknowledgeButton ids={openReenquiries.map((q) => q.id)} />
          </div>
          <p className="mb-2 text-[12.5px] text-muted">Recorded on the lead and never re-routed (R2–R4). {openReenquiries.some((q) => q.holder === "partner") ? "The partner keeps the lead." : ""}</p>
          <ul className="space-y-1.5 text-[13px]">
            {r.reenquiries.map((q) => (
              <li key={q.id} className="flex flex-wrap items-center gap-x-2 gap-y-0.5">
                <span className="text-fg">{q.source_system ? humanize(q.source_system) : q.kind === "witty_message" ? "Witty" : "Touchpoint"}{q.event_type ? ` · ${humanize(q.event_type.replace(/\./g, " "))}` : ""}{q.campaign ? ` · ${q.campaign}` : ""}</span>
                {q.interest && <Badge tone="success">interest</Badge>}
                {q.paid_label && <Badge tone="info">{q.paid_label}</Badge>}
                <span className="text-[12px] text-muted">{reenquiryHolderText(q)}</span>
                <span className="text-[12px] text-subtle" title={formatDateTime(q.occurred_at)}>{relativeTime(q.occurred_at)}</span>
                {q.acknowledged_at && <Badge>acknowledged{q.note ? ` · ${q.note}` : ""}</Badge>}
              </li>
            ))}
          </ul>
        </section>
      )}

      {nurture && (
        <section className="px-5 py-4">
          <H3><ListChecks className="size-3.5" /> Qualification nurture</H3>
          <div className="space-y-1 text-[13px]">
            <p className="text-fg">
              {nurture.active ? <>With B2C to get the missing details{nurture.reason ? <span className="text-muted"> · {nurture.reason}</span> : null}.</> : "No longer in qualification nurture."}
            </p>
            {nurture.missing.length > 0 && <p className="text-muted">Still missing: {nurture.missing.join(", ")}.</p>}
            {nurture.awaitingConsent && <p className="text-muted">Qualified now; waiting for the partner-sharing consent request before it returns to routing.</p>}
            {nurture.qualifiedAt && !nurture.awaitingConsent && <p className="text-muted">Qualified {formatDateTime(nurture.qualifiedAt)}.</p>}
            <p className="text-[12px] text-subtle">
              {nurture.lastCheck ? <>Last check <span title={formatDateTime(nurture.lastCheck)}>{relativeTime(nurture.lastCheck)}</span></> : "Not checked yet"}
              {nurture.times > 0 ? ` · ${nurture.times} ${nurture.times === 1 ? "check" : "checks"}` : ""}
              {nurture.nextCheck ? ` · next ${formatDateTime(nurture.nextCheck)}` : ""}
              {nurture.reengagedAt ? ` · re-engaged ${relativeTime(nurture.reengagedAt)}` : ""}
              {nurture.active ? " · it returns to routing the moment it qualifies (R7 → R9)" : ""}
            </p>
          </div>
        </section>
      )}

      {grace && (
        <section className="px-5 py-4">
          <H3><Hourglass className="size-3.5" /> Lost at the partner</H3>
          <div className="space-y-1 text-[13px]">
            <p className="text-fg">
              {grace.partner ?? "The partner"} marked it lost <span title={formatDateTime(grace.lostAt)}>{relativeTime(grace.lostAt)}</span>
              {grace.lostReason ? <span className="text-muted"> · {grace.lostReason}</span> : null}
              {grace.lostCount && grace.lostCount > 1 ? <span className="text-muted"> · {grace.lostCount} times</span> : null}.
            </p>
            {grace.inGrace ? (
              <p className="text-fg">
                <Badge tone="warning">In grace · {grace.remaining}</Badge>
                <span className="ml-2 text-muted">until {formatDateTime(grace.graceUntil)}. New partner activity brings it back with no dispute; otherwise it moves to B2C nurture, unassigned and partner-barred.</span>
              </p>
            ) : grace.revived ? (
              <p className="text-muted">Back with the partner {grace.revivedAt ? relativeTime(grace.revivedAt) : ""}: activity was reported inside the grace. A new lost report starts a fresh 7 days.</p>
            ) : (
              <p className="text-muted">The grace ended; the lead moved to B2C nurture.</p>
            )}
          </div>
        </section>
      )}

      <section className="px-5 py-4">
        <div className="mb-2 flex items-center justify-between gap-2">
          <H3>Interests</H3>
          <InterestsEditor leadId={leadId} interests={r.interests} />
        </div>
        <ol className="space-y-1 text-[13px]">
          {(r.interests.length ? r.interests : [r.interest]).map((i, k) => (
            <li key={i.interest_id ?? `p${k}`} className="flex flex-wrap items-center gap-x-2 gap-y-0.5">
              <span className="tabular text-subtle">{i.rank ?? k + 1}.</span>
              <span className="text-fg">{i.course_text ?? i.course_key ?? "—"}{i.specialization ? ` (${i.specialization})` : ""}</span>
              <Badge>{segmentLabel(i.segment_exact ?? i.segment)}</Badge>
              {i.university_text && <span className="text-[12px] text-muted">{i.university_text}</span>}
              {(i.rank ?? k + 1) === 1 ? <span className="text-[12px] text-subtle">first choice</span> : i.source ? <span className="text-[12px] text-subtle">from {humanize(i.source)}</span> : null}
            </li>
          ))}
        </ol>
        {secondary.length === 0 && <p className="mt-1 text-[12px] text-subtle">No other interests: when no partner offers the first choice, the lead goes to B2C (no partner offers this programme).</p>}
      </section>

      {r.allocations.length > 0 && (
        <section className="px-5 py-4">
          <H3>Allocations</H3>
          <ul className="space-y-2 text-[13px]">
            {r.allocations.map((a) => (
              <li key={a.id} className="flex flex-wrap items-center gap-x-2 gap-y-1">
                <span className="font-mono text-[12px] text-fg">{a.reference}</span>
                <span className="text-fg">{a.destination_type === "partner" ? a.partner_name : LANE_LABEL[a.b2c_lane ?? "sales"]}</span>
                <Badge tone={a.outcome === "lost" || (a.lost_at && !a.lost_revived_at) ? "warning" : a.destination_type === "partner" ? "info" : "neutral"}>{allocationStatusText(a)}</Badge>
                {a.is_test && <Badge tone="brand">test</Badge>}
                {a.reason && (a.destination_type === "in_house" || a.reason !== "rule") && <span className="text-[12px] text-muted">{reasonLabel(a.reason, a.cause)}</span>}
                {a.stage && a.destination_type === "partner" && <span className="text-[12px] text-muted">Stage {a.stage}</span>}
                {a.origin && a.origin !== "auto" && <span className="text-[12px] text-muted">{ORIGIN_LABEL[a.origin] ?? a.origin}</span>}
                {a.recall_reason && <span className="text-[12px] text-muted">recalled: {a.recall_reason}</span>}
                <span className="text-[12px] text-subtle" title={formatDateTime(a.created_at)}>{relativeTime(a.created_at)}</span>
              </li>
            ))}
          </ul>
        </section>
      )}

      {(r.notifications ?? []).length > 0 && (
        <section className="px-5 py-4">
          <H3>Messages to the student</H3>
          <ul className="space-y-2 text-[13px]">
            {(r.notifications ?? []).map((n) => (
              <li key={n.id} className="flex flex-wrap items-center gap-x-2 gap-y-1">
                <span className="text-fg">{CHANNEL_LABEL[n.channel]}</span>
                <Badge tone={NOTIFY_TONE[n.status] ?? "neutral"}>{NOTIFY_LABEL[n.status] ?? n.status}</Badge>
                {n.kind && n.kind !== "accepted" && <span className="text-[12px] text-muted">{humanize(n.kind)}</span>}
                {n.partner_name && <span className="text-[12px] text-muted">{n.partner_name}</span>}
                {n.error && <span className="text-[12px] text-muted">{n.error}</span>}
                <span className="text-[12px] text-subtle" title={formatDateTime(n.sent_at ?? n.scheduled_for ?? n.created_at)}>
                  {n.status === "scheduled" && n.scheduled_for ? `due ${formatDateTime(n.scheduled_for)}` : relativeTime(n.sent_at ?? n.created_at)}
                </span>
              </li>
            ))}
          </ul>
        </section>
      )}

      <section className="px-5 py-4">
        <H3>Decisions</H3>
        {r.decisions.length === 0 ? (
          <p className="text-[13px] text-muted">Not routed yet.</p>
        ) : (
          <ul className="space-y-2 text-[13px]">
            {r.decisions.map((d) => (
              <li key={d.id}>
                <Link href={`/routing/decisions/${d.id}`} className="text-fg hover:underline">
                  {d.destination_type === "partner"
                    ? `To ${d.partner_name} · ${decisionModeLabel(d)}`
                    : `To ${LANE_LABEL[d.b2c_lane ?? "sales"]} · ${reasonLabel(d.reason, d.allocation?.cause)}`}
                </Link>
                <span className="block text-[12px] text-subtle">
                  <span title={formatDateTime(d.created_at)}>{relativeTime(d.created_at)}</span>
                  {" · "}{d.actor_type === "engine" ? "automatic" : "by an Admin"}
                  {d.how && d.how !== "auto" ? ` · ${ORIGIN_LABEL[d.how] ?? humanize(d.how)}` : ""}
                  {d.interest_rank && d.interest_rank > 1 ? ` · interest ${d.interest_rank}` : ""}
                  {" · "}{(d.candidates ?? []).length} candidates
                  {d.is_test ? " · test" : ""}
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
