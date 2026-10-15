import Link from "next/link";
import { ArrowLeft, ArrowRight, History, MessageCircle, Users } from "lucide-react";
import type { Me } from "@/lib/auth";
import { firstName } from "@/lib/compose";
import { maskPhone, when } from "@/lib/format";
import { CONSENT_LABEL, reasonLabel, STATUS_LABEL, TASK_KIND_LABEL } from "@/lib/labels";
import type { LeadDetail, Stage, SubStage } from "@/lib/types";
import { ApplicationsPanel } from "./Applications";
import { CallButton } from "./CallButton";
import { EmailButton } from "./EmailButton";
import { BriefPanel } from "./BriefPanel";
import { LeadTabs } from "./LeadTabs";
import { NurturePanel } from "./NurturePanel";
import { BarChip, FlagChip, SlaChip, TempChip, TestChip } from "./Chips";
import { AddTaskButton, ContactsPanel, EditablePanel, NoteBox, type FieldDef } from "./Panels";
import { ProgrammeFit } from "./ProgrammeFit";
import { QualifyPanel } from "./QualifyPanel";
import { StageButton } from "./StageButton";
import { TaskActions } from "./TaskActions";
import { Timeline } from "./Timeline";
import { Hotkeys } from "@/components/shell/Hotkeys";
import { WittyTranscript } from "./WittyTranscript";

const g = (rec: LeadDetail["record"], group: string, key: string): string | null => {
  const grp = rec?.[group] as Record<string, unknown> | undefined;
  const v = grp?.[key];
  return v === null || v === undefined || v === "" ? null : Array.isArray(v) ? v.join(", ") : String(v);
};

/**
 * The lead (spec B8.3): who they are and what to do next at the top, the four actions, then one section at a time:
 * Overview (brief, contacts, interest, programme fit), Profile, Applications; follow-ups, nurture and the timeline in the
 * activity rail. Values still waiting to reach the master lead table (pending) are shown as the counsellor typed them.
 */
export function LeadScreen({ d, stages, subs, me, base, adminTools, next }: { d: LeadDetail; stages: Stage[]; subs: SubStage[]; me: Me; base: string; adminTools?: React.ReactNode; next?: { id: number; name: string | null; left: number } | null }) {
  const l = d.lead!;
  const pend = d.pending as Record<string, unknown>;
  const val = (group: string, key: string) => (key in pend ? (pend[key] === null ? null : String(pend[key])) : g(d.record, group, key));
  const mine = l.owner_id === me.user_id;
  const canWork = l.status === "active" && (mine || me.role === "admin" || me.role === "sales_head");
  // B10.2: the Admin edits any lead, pooled and closed included; calling and messaging stay with active leads
  const canEdit = canWork || me.role === "admin";
  const qualifyTask = d.tasks.some((t) => t.kind === "qualify" && t.owner_id === me.user_id) || (me.role === "admin" && (l.tags ?? []).includes("to_qualify"));
  const partner = partnerHistory(d.timeline);
  const handling = (l.handling ?? {}) as Record<string, string | null>;
  const providers = (l.providers ?? []) as { partner_name: string; first_had_at: string | null }[];
  const others = g(d.record, "interest", "other_courses");

  const interest: FieldDef[] = [
    { key: "course", label: "Programme", value: val("interest", "course") },
    { key: "specialization", label: "Specialization", value: val("interest", "specialization") },
    { key: "university", label: "University", value: val("interest", "university") },
    { key: "programme_level", label: "Level", value: val("interest", "programme_level") },
    { key: "study_mode", label: "Mode", value: val("interest", "study_mode") },
    { key: "enrollment_timeline", label: "Timeline", value: val("interest", "enrollment_timeline") },
    { key: "annual_budget_inr", label: "Budget (₹ a year)", value: val("interest", "annual_budget_inr"), type: "number" },
  ];
  const profile: FieldDef[] = [
    { key: "name", label: "Name", value: val("student", "name") },
    { key: "city", label: "City", value: val("student", "city") },
    { key: "state", label: "State", value: val("student", "state") },
    { key: "preferred_language", label: "Language", value: val("student", "preferred_language") },
    { key: "highest_qualification", label: "Qualification", value: val("education", "highest_qualification") },
    { key: "academic_score_pct", label: "Score (%)", value: val("education", "academic_score_pct"), type: "number" },
    { key: "work_experience_years", label: "Work experience (years)", value: val("education", "work_experience_years"), type: "number" },
    { key: "current_job_role", label: "Job", value: val("education", "current_job_role") },
    { key: "guardian_name", label: "Guardian", value: val("student", "guardian_name") },
    { key: "preferred_counseling_time", label: "Best time to call", value: val("interest", "preferred_counseling_time") },
  ];

  const email = d.contacts.filter((c) => c.kind === "email").sort((a, b) => Number(b.primary_email) - Number(a.primary_email))[0]?.value ?? null;
  const first = firstName(val("student", "name"));
  const nextTask = d.tasks[0];

  const followups = (
    <section className="panel">
      <header><h3>Follow-ups</h3>{canEdit && <AddTaskButton leadId={l.lead_id} />}</header>
      <div className="body small">
        {d.tasks.length === 0 && <p className="note">No open follow-up.</p>}
        {d.tasks.map((t) => (
          <div key={t.id} className="row between wrap">
            <div><b>{TASK_KIND_LABEL[t.kind] ?? t.kind}</b> · {t.title}<div className={new Date(t.due_at) < new Date() ? "error" : "muted"}>{when(t.due_at)}</div></div>
            {canEdit && <TaskActions taskId={t.id} title={t.title} leadId={l.lead_id} />}
          </div>
        ))}
      </div>
    </section>
  );

  return (
    <div className="content">
      {canWork && <Hotkeys keys={[{ key: "c", label: "Call" }, { key: "w", label: "WhatsApp" }, { key: "e", label: "Email" }, { key: "f", label: "Add a follow-up" }, { key: "n", label: "Write a note" }, { key: "s", label: "Change the stage" }, { key: "]", label: "Next lead in the queue" }]} />}
      <div className="row">
        <Link className="btn quiet sm icon-only" href={base} aria-label="Back to leads"><ArrowLeft className="icon s" aria-hidden /></Link>
        <span className="small muted grow ellipsis">Lead #{l.lead_id} · {STATUS_LABEL[l.status] ?? l.status}{l.owner_name ? ` · ${l.owner_name}` : ""}</span>
        <TestChip on={l.is_test} />
        {next && <Link className="btn ghost sm" data-hotkey="]" href={`${base}/${next.id}`} title={`${next.left} more in your queue`}>Next: {(next.name ?? "lead").split(" ")[0]} <ArrowRight className="icon s" aria-hidden /></Link>}
      </div>

      <div className="lead-head card pad">
        <div className="row" style={{ alignItems: "flex-start" }}>
          <div className="grow">
            <h1>{l.name ?? "Name not given"} <TempChip t={l.temperature} /></h1>
            <div className="small muted" style={{ marginTop: 4 }}><span className="mono">{maskPhone(l.phone)}</span>{l.city ? ` · ${l.city}` : ""}{l.language ? ` · ${l.language}` : ""}</div>
          </div>
        </div>
        <div className="row wrap" style={{ gap: 6 }}>
          <span data-hotkey="s" className="contents"><StageButton leadId={l.lead_id} current={l.stage_id} sub={l.sub_stage} stages={stages} subs={subs} canMoveBack={me.role === "admin" || me.role === "sales_head"} disabled={!canEdit} /></span>
          <SlaChip lead={l} />
          <BarChip reason={l.partner_bar_reason} />
          <FlagChip flag={l.flagged} />
          {l.opted_out && <span className="chip breach">Opted out: do not message</span>}
          <span className="chip line">{reasonLabel(l.handoff_reason)}{l.reengage_trigger ? ` · re-engaged` : ""}</span>
        </div>
        {providers.length > 0 && (
          <div className="banner"><Users className="icon" aria-hidden /><div><b>Already with other providers.</b> {providers.map((p) => `${p.partner_name}${p.first_had_at ? ` (since ${when(p.first_had_at)})` : ""}`).join(" · ")}. Open as a neutral adviser: &ldquo;Eduwit can help you compare your options.&rdquo;</div></div>
        )}
        {partner && (
          <div className="banner"><History className="icon" aria-hidden /><div>
            <b>Lost by {partner.lost?.partner_name ?? "a partner"}</b>{partner.lost?.lost_reason ? `: ${partner.lost.lost_reason}` : ""}{partner.mapped ? ` (${partner.mapped})` : ""}
            {partner.lost?.partner_status ? ` · their status ${[partner.lost.partner_status, partner.lost.partner_sub_status].filter(Boolean).join(" / ")}` : ""}
            {partner.lost?.calls_made !== undefined ? ` · ${partner.lost.calls_made} calls made` : ""}
            {partner.tried.length > 0 && <div className="small">Partners tried ({partner.tried.length}): {partner.tried.map((t) => `${t.partner_name ?? "?"}${t.outcome ?? t.status ? ` (${t.outcome ?? t.status})` : ""}`).join(", ")}</div>}
          </div></div>
        )}
        {handling.first_contact_script === "neutral_adviser" && providers.length === 0 && (
          <div className="banner info">Open as a neutral adviser: &ldquo;Eduwit can help you compare your options.&rdquo;</div>
        )}
        {canWork && (
          <div className="lead-actions">
            <span data-hotkey="c" className="contents"><CallButton leadId={l.lead_id} name={l.name ?? "the student"} pending={d.unlogged_call} /></span>
            <Link className="btn ghost" data-hotkey="w" href={`/s/inbox?lead=${l.lead_id}`}><MessageCircle className="icon s" aria-hidden />WhatsApp</Link>
            <span data-hotkey="e" className="contents"><EmailButton leadId={l.lead_id} to={email} blocked={l.opted_out ? "This student opted out: do not message." : null}
              vars={{ first_name: first, programme: val("interest", "course"), university: val("interest", "university"), counsellor: me.full_name }} /></span>
            <span data-hotkey="f" className="contents"><AddTaskButton leadId={l.lead_id} label="Follow-up" className="btn ghost" /></span>
          </div>
        )}
        <div className="next-line">
          <span>Next</span>
          {nextTask ? <><b>{nextTask.title}</b><span>{when(nextTask.due_at)}</span></> : <b>nothing planned</b>}
        </div>
      </div>

      <LeadTabs
        tabs={[
          { id: "overview", label: "Overview", content: (
            <>
              {qualifyTask && <QualifyPanel leadId={l.lead_id} missing={l.missing}
                known={{ course: val("interest", "course"), highest_qualification: val("education", "highest_qualification"), enrollment_timeline: val("interest", "enrollment_timeline"),
                  annual_budget_inr: val("interest", "annual_budget_inr"), study_mode: val("interest", "study_mode"), specialization: val("interest", "specialization"), name: val("student", "name"), email }} />}
              <BriefPanel leadId={l.lead_id} autoWrite={canWork} />
              {adminTools}
              <div className="grid g2">
                <ContactsPanel leadId={l.lead_id} contacts={d.contacts} canEdit={canEdit} />
                <EditablePanel leadId={l.lead_id} title="Interest" fields={interest} reasonRequired canEdit={canEdit} note={others ? `Also interested in: ${others}` : undefined} />
              </div>
              <ProgrammeFit leadId={l.lead_id} canShare={canWork && !l.opted_out} firstName={first} counsellor={me.full_name} hasEmail={!!email} />
            </>
          ) },
          { id: "profile", label: "Profile", content: (
            <>
              <EditablePanel leadId={l.lead_id} title="Profile" fields={profile} canEdit={canEdit} />
              <section className="panel">
                <header><h3>Consent and source</h3></header>
                <div className="body">
                  <dl className="kv">
                    <dt>Partner sharing</dt><dd>{CONSENT_LABEL[l.partner_consent_state ?? "none"] ?? l.partner_consent_state}</dd>
                    <dt>Marketing</dt><dd>{l.marketing_consent ? "Yes" : "No"}</dd>
                    <dt>Source</dt><dd>{l.source ?? "—"}{l.campaign ? ` · ${l.campaign}` : ""}</dd>
                    <dt>Handed to Spark</dt><dd>{when(l.handed_off_at)}</dd>
                    <dt>First contact</dt><dd>{when(l.first_contacted_at)} ({l.contact_attempts} attempts)</dd>
                  </dl>
                </div>
              </section>
            </>
          ) },
          { id: "applications", label: "Applications", content: (
            <ApplicationsPanel leadId={l.lead_id} apps={d.applications} enrollments={d.enrollments} canEdit={canEdit}
              defaultProgramme={val("interest", "course")} defaultUniversity={val("interest", "university")} />
          ) },
        ]}
        aside={
          <>
            {followups}
            <Timeline items={d.timeline}>{canEdit && <span data-hotkey="n" className="contents"><NoteBox leadId={l.lead_id} /></span>}</Timeline>
            <NurturePanel leadId={l.lead_id} marketing={me.role === "admin" || me.role === "marketing"} canWork={canWork} inPool={l.status === "pool"} optedOut={l.opted_out} />
            <WittyTranscript leadId={l.lead_id} />
          </>
        }
      />
    </div>
  );
}

type PartnerLost = { partner_name?: string; lost_reason?: string; partner_status?: string; partner_sub_status?: string; calls_made?: number | string };

/** The partner's history (b39 activity "partner_history"): who lost the lead and why, the mapped lost sub-stage, the partners tried. */
function partnerHistory(timeline: LeadDetail["timeline"]): { lost: PartnerLost | null; mapped: string | null; tried: { partner_name?: string; outcome?: string; status?: string }[] } | null {
  const a = timeline.find((t) => t.kind === "partner_history");
  if (!a) return null;
  const m = a.meta ?? {};
  return { lost: (m.lost as PartnerLost | undefined) ?? null, mapped: typeof m.mapped_sub_stage === "string" ? m.mapped_sub_stage : null,
    tried: Array.isArray(m.partners_tried) ? (m.partners_tried as { partner_name?: string; outcome?: string; status?: string }[]) : [] };
}
