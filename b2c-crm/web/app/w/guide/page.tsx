import type { Metadata } from "next";
import { Page } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { GUIDE } from "@/app/s/me/guide";

export const metadata: Metadata = { title: "Guide" };

const ADMIN_GUIDE: { title: string; body: string[] }[] = [
  { title: "Where leads come from", body: [
    "The B2B CRM decides every lead first. When it hands one to B2C you see it here within seconds: the sales lane goes to a counsellor through Lead Allocation; the nurture lane goes to the pool.",
    "Counsellors and you can add students too (New lead). They go in through the master lead table so a student is never created twice, and come straight back.",
  ] },
  { title: "Lead Allocation", body: [
    "Rules run top to bottom; the first that matches decides. Each picks from its pool among people working now, not on leave or away, and under their caps. The catch-all is always last.",
    "Every decision is kept with the people it skipped and why (Decisions tab, and on each lead). Run a simulation before changing a rule that matters.",
    "Leads nobody can take wait in Queues; the engine retries every minute and alerts you after 5 minutes in working hours.",
  ] },
  { title: "Every hand-off is recorded in the B2B CRM", body: [
    "A lead goes to a partner only through the B2B engine (Send to partner routing). Each counsellor assignment, reassignment and its end is sent to the B2B CRM at once, so the B2B ledger shows who had each student and when, whether a partner or one of our counsellors.",
  ] },
  { title: "Enrolments", body: [
    "A counsellor records the enrolment with the fee, the date and the proof. Check the proof and verify it, or send it back saying what is missing. Only verified enrolments count.",
  ] },
  { title: "Test leads and test users", body: [
    "Phones starting 910000 or 9190000000 are test leads. They go only to test users or to you, never reach a student, and stay out of reports.",
  ] },
];

export default async function GuidePage() {
  const me = await requireUser("workspace", "/w/guide");
  const sections = me.role === "admin" ? [...ADMIN_GUIDE, ...GUIDE] : GUIDE;
  return (
    <Page title="Guide">
      <div className="stack">
        {sections.map((s) => (
          <details key={s.title} className="panel more" style={{ padding: 12 }}>
            <summary>{s.title}</summary>
            <div className="stack" style={{ marginTop: 8 }}>{s.body.map((p, i) => <p key={i}>{p}</p>)}</div>
          </details>
        ))}
      </div>
    </Page>
  );
}
