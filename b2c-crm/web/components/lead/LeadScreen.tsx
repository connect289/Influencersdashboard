import Link from "next/link";
import { ArrowLeft, MessageCircle, Users } from "lucide-react";
import type { Me } from "@/lib/auth";
import { firstName } from "@/lib/compose";
import { maskPhone, when } from "@/lib/format";
import { CONSENT_LABEL, reasonLabel, STATUS_LABEL, TASK_KIND_LABEL } from "@/lib/labels";
import type { LeadDetail, Stage, SubStage } from "@/lib/types";
import { ApplicationsPanel } from "./Applications";
import { CallButton } from "./CallButton";
import { EmailButton } from "./EmailButton";
import { BarChip, SlaChip, TempChip, TestChip } from "./Chips";
import { AddTaskButton, ContactsPanel, EditablePanel, NoteBox, type FieldDef } from "./Panels";
import { ProgrammeFit } from "./ProgrammeFit";
import { StageButton } from "./StageButton";
import { TaskActions } from "./TaskActions";
import { Timeline } from "./Timeline";
import { WittyTranscript } from "./WittyTranscript";

const g = (rec: LeadDetail["record"], group: string, key: string): string | null => {
  const grp = rec?.[group] as Record<string, unknown> | undefined;
  const v = grp?.[key];
  return v === null || v === undefined || v === "" ? null : Array.isArray(v) ? v.join(", ") : String(v);
};

/**
 * The lead (spec B8.5): who, why with us, what to do next; contacts, interest, profile, applications, follow-ups and the
 * timeline. Values still waiting to reach the master lead table (pending) are shown as the counsellor typed them.
 */
export function LeadScreen({ d, stages, subs, me, base, adminTools }: { d: LeadDetail; stages: Stage[]; subs: SubStage[]; me: Me; base: string; adminTools?: React.ReactNode }) {
  const l = d.lead!;
  const pend = d.pending as Record<string, unknown>;
  const val = (group: string, key: string) => (key in pend ? (pend[key] === null ? null : String(pend[key])) : g(d.record, group, key));
  const mine = l.owner_id === me.user_id;
  const canWork = l.status === "active" && (mine || me.role === "admin" || me.role === "sales_head");
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
  const timeline = <Timeline items={d.timeline}>{canWork && <NoteBox leadId={l.lead_id} />}</Timeline>;

  const tasks = (
    <section className="panel">
      <header><h3>Follow-ups</h3>{canWork && <AddTaskButton leadId={l.lead_id} />}</header>
      <div className="body small">
        {d.tasks.length === 0 && <p className="note">No open follow-up.</p>}
        {d.tasks.map((t) => (
          <div key={t.id} className="row between wrap">
            <div><b>{TASK_KIND_LABEL[t.kind] ?? t.kind}</b> · {t.title}<div className={new Date(t.due_at) < new Date() ? "error" : "muted"}>{when(t.due_at)}</div></div>
            {canWork && <TaskActions taskId={t.id} title={t.title} leadId={l.lead_id} />}
          </div>
        ))}
      </div>
    </section>
  );

  return (
    <div className="content">
      <div className="row">
        <Link className="btn quiet sm" href={base} aria-label="Back to leads"><ArrowLeft className="icon s" aria-hidden /></Link>
        <span className="small muted grow">Lead #{l.lead_id} · {STATUS_LABEL[l.status] ?? l.status}{l.owner_name ? ` · ${l.owner_name}` : ""}</span>
        <TestChip on={l.is_test} />
      </div>
      <div className="grid g-lead">
        <div className="stack">
          <div className="lead-head card pad">
            <div className="row">
              <div className="grow">
                <h1 style={{ fontSize: 20 }}>{l.name ?? "Name not given"} <TempChip t={l.temperature} /></h1>
                <div className="small muted"><span className="mono">{maskPhone(l.phone)}</span>{l.city ? ` · ${l.city}` : ""}{l.language ? ` · ${l.language}` : ""}</div>
              </div>
            </div>
            <div className="row wrap" style={{ gap: 6 }}>
              <StageButton leadId={l.lead_id} current={l.stage_id} sub={l.sub_stage} stages={stages} subs={subs} canMoveBack={me.role === "admin" || me.role === "sales_head"} disabled={!canWork} />
              <SlaChip lead={l} />
              <BarChip reason={l.partner_bar_reason} />
              {l.opted_out && <span className="chip breach">Opted out: do not message</span>}
            </div>
            <p className="small"><span className="muted">Why with us:</span> {reasonLabel(l.handoff_reason)}{l.reengage_trigger ? ` · re-engaged (${l.reengage_trigger})` : ""}</p>
            {providers.length > 0 && (
              <div className="banner"><Users className="icon" aria-hidden /><div><b>Already with other providers.</b> {providers.map((p) => `${p.partner_name}${p.first_had_at ? ` (since ${when(p.first_had_at)})` : ""}`).join(" · ")}. Open as a neutral adviser: &ldquo;Eduwit can help you compare your options.&rdquo;</div></div>
            )}
            {handling.first_contact_script === "neutral_adviser" && providers.length === 0 && (
              <div className="banner info">Open as a neutral adviser: &ldquo;Eduwit can help you compare your options.&rdquo;</div>
            )}
            {canWork && (
              <div className="lead-actions">
                <CallButton leadId={l.lead_id} name={l.name ?? "the student"} pending={d.unlogged_call} />
                <Link className="btn ghost" href={`/s/inbox?lead=${l.lead_id}`}><MessageCircle className="icon s" aria-hidden />WhatsApp</Link>
                <EmailButton leadId={l.lead_id} to={email} blocked={l.opted_out ? "This student opted out: do not message." : null}
                  vars={{ first_name: first, programme: val("interest", "course"), university: val("interest", "university"), counsellor: me.full_name }} />
                <Link className="btn ghost" href={`#tasks`}>Follow-up</Link>
              </div>
            )}
            <div className="row small"><span className="muted">Next:</span><b>{d.tasks[0]?.title ?? "—"}</b><span className="muted">{when(d.tasks[0]?.due_at)}</span></div>
          </div>
          {adminTools}
          <div className="grid g2">
            <ContactsPanel leadId={l.lead_id} contacts={d.contacts} canEdit={canWork} />
            <EditablePanel leadId={l.lead_id} title="Interest" fields={interest} reasonRequired canEdit={canWork} note={others ? `Also interested in: ${others}` : undefined} />
          </div>
          <ProgrammeFit leadId={l.lead_id} canShare={canWork && !l.opted_out} firstName={first} counsellor={me.full_name} hasEmail={!!email} />
          <EditablePanel leadId={l.lead_id} title="Profile" fields={profile} canEdit={canWork} />
          <ApplicationsPanel leadId={l.lead_id} apps={d.applications} enrollments={d.enrollments} canEdit={canWork}
            defaultProgramme={val("interest", "course")} defaultUniversity={val("interest", "university")} />
        </div>
        <div className="stack">
          <div id="tasks">{tasks}</div>
          <section className="panel">
            <header><h3>Consent and source</h3></header>
            <div className="body">
              <dl className="kv">
                <dt>Partner sharing</dt><dd>{CONSENT_LABEL[l.partner_consent_state ?? "none"] ?? l.partner_consent_state}</dd>
                <dt>Marketing</dt><dd>{l.marketing_consent ? "Yes" : "No"}</dd>
                <dt>Source</dt><dd>{l.source ?? "—"}{l.campaign ? ` · ${l.campaign}` : ""}</dd>
                <dt>Handed to B2C</dt><dd>{when(l.handed_off_at)}</dd>
                <dt>First contact</dt><dd>{when(l.first_contacted_at)} ({l.contact_attempts} attempts)</dd>
              </dl>
            </div>
          </section>
          <WittyTranscript leadId={l.lead_id} />
          {timeline}
        </div>
      </div>
    </div>
  );
}
