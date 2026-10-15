import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { when } from "@/lib/format";
import { createClient } from "@/lib/supabase/server";
import Link from "next/link";
import { SettingEditor } from "./SettingEditor";
import { HealthPanel } from "./Health";
import { AuditPanel, SignInsPanel } from "./Logs";

export const metadata: Metadata = { title: "Settings" };

const ABOUT: Record<string, string> = {
  live_mode: "Real messages to students. Both this and the server's LIVE_MODE must be on; test leads never receive real messages either way.",
  working_defaults: "Company working days (1 = Monday) and hours, used for anyone without their own pattern.",
  sla_minutes: "First-contact limits in working minutes, by temperature.",
  allocation: "Admin takes leads when nobody else can; non-hot leads outside hours; when to alert about unassigned leads; capacity alerts.",
  followups: "Reminder before a follow-up, escalation after a missed one, the unlogged-call flag, untouched-lead alert.",
  sync: "How often the batch goes to the master lead table and how often the feeds are reconciled (the timers are in the database).",
  messaging: "Quiet hours and marketing frequency caps; how long to wait after Witty's last message before the counsellor's intro.",
  test_phones: "Phone prefixes that mark a test lead.",
  opt_out_words: "Replies that opt a student out of every message at once.",
  app: "The app's address, used by the database timers to call the sync jobs.",
  telephony: "Calls through a provider. provider: none (counsellors dial from their own phones and log by hand), exotel, or mock (a rehearsal: nobody is dialled). With a provider every call is recorded; retention_days says how long recordings are kept; missed_call_minutes is when the call-back task falls due. caller_id is the Exotel virtual number.",
  money: "Eduwit's billing details, GST, SAC, invoice prefixes, payment terms, the refund window, the tier denominator and the commission run day. To be confirmed by the CA (then set ca_confirmed to true).",
  ai: "Claude: the model, the daily spend cap in rupees, the exchange rate and prices used for the cost log, and the hour the morning insights are written.",
  support: "Support tickets: developer_emails (where every ticket and reply is emailed), mailbox (the Workspace mailbox tickets are sent from and answers are read back from; it needs the gmail.send and gmail.readonly delegation), auto_close_days (a ticket marked fixed closes by itself after this many days).",
  performance: "Targets and the leaderboard: whether counsellors see the leaderboard, and when a lead counts as untouched.",
};

/** Settings (spec B14): every change needs a reason and is versioned. */
const TABS = [["settings", "Settings"], ["health", "System health"], ["audit", "Audit log"], ["signins", "Sign-ins"]] as const;

export default async function SettingsPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const me = await requireUser("workspace", "/w/settings");
  if (me.role !== "admin") redirect("/w");
  const sp = await searchParams;
  const tab = TABS.some(([k]) => k === sp.tab) ? sp.tab! : "settings";
  const tabs = (
    <div className="tabs" role="tablist">
      {TABS.map(([k, n]) => <Link key={k} href={`/w/settings?tab=${k}`} role="tab" aria-selected={tab === k}>{n}</Link>)}
    </div>
  );
  if (tab !== "settings") {
    return (
      <Page title="Settings" sub={tab === "health" ? "Is everything running? The timers, the queues, the feeds, the app and Claude." : tab === "audit" ? "Every phone reveal, Call tap, export, contact edit and delete, with who and when." : "Every sign-in attempt, newest first."}>
        {tabs}
        {tab === "health" ? <HealthPanel /> : tab === "audit" ? <AuditPanel sp={sp} /> : <SignInsPanel sp={sp} />}
      </Page>
    );
  }
  const supabase = await createClient();
  const { data, error } = await supabase.from("settings").select("key, value, version, updated_at").order("key");
  if (error) return <Page title="Settings"><SetupError error={error.message} /></Page>;
  return (
    <Page title="Settings" sub="Every change needs a reason and is kept as a new version.">
      {tabs}
      <div className="stack">
        {(data ?? []).map((s) => (
          <section key={s.key} className="panel">
            <header><h3>{s.key.replace(/_/g, " ")}</h3><span className="small muted">version {s.version} · {when(s.updated_at)}</span></header>
            <div className="body">
              {ABOUT[s.key] && <p className="note">{ABOUT[s.key]}</p>}
              <SettingEditor k={s.key} value={s.value} />
            </div>
          </section>
        ))}
      </div>
    </Page>
  );
}
