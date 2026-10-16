import type { Metadata } from "next";
import { Check, CircleAlert } from "lucide-react";
import { Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { b2bReady } from "@/lib/b2b";
import { rpc } from "@/lib/data";
import { directoryConfig } from "@/lib/directory";
import { liveMode } from "@/lib/env";
import { pushConfig } from "@/lib/push";
import { when } from "@/lib/format";
import { adminClient } from "@/lib/supabase/admin";
import { googleSa } from "@/lib/gmail";
import { exotelConfig } from "@/lib/telephony";
import { CalendarToggle, UnknownCallDone, type CalendarMine } from "@/components/connectors/CalendarToggle";
import { createClient } from "@/lib/supabase/server";
import { Overview, type ConnectorsOverview } from "./Overview";
import { ImportTemplatesButton } from "./ImportTemplates";

export const metadata: Metadata = { title: "Connectors" };

function Status({ ok, children }: { ok: boolean; children: React.ReactNode }) {
  return ok ? <span className="chip ok"><Check className="icon s" aria-hidden />{children}</span> : <span className="chip risk"><CircleAlert className="icon s" aria-hidden />{children}</span>;
}

type Telephony = { settings: { provider?: string; caller_id?: string | null; retention_days?: number }; last_event: string | null; events_24h: number; bridged_7d: number;
  recordings: Record<string, number> | null; unknown_calls: { id: number; from_number: string; status: string; at: string }[]; agents_without_phone: string[] };
type CalStatus = { user_id: string; name: string; on: boolean; error: string | null; synced_at: string | null; pending: number; failed: number }[];
type Sync = { last_batch_at: string | null; queued: number; failed: number; inbox_errors: number; last_received_at: string | null };

/** Connectors (spec B14): the B2B link, WhatsApp, email, and what is waiting or failed. Problems are shown to the Admin only in detail. */
export default async function ConnectorsPage() {
  const me = await requireUser("workspace", "/w/connectors");
  const admin = me.role === "admin";
  let sync: Sync;
  let templates: { name: string; language: string; audience: string; purpose: string | null; status: string }[] = [];
  let problems: { id: number; kind: string; lead_id: number | null; status: string; attempts: number; answer: { error?: string } | null; done_at: string | null }[] = [];
  let inboxErrors: { envelope_id: string; type: string; lead_id: number | null; error: string | null; received_at: string }[] = [];
  let live: { whatsapp?: boolean; email?: boolean } = {};
  let tel: Telephony | null = null, cal: CalStatus = [], mine: CalendarMine | null = null, telProvider = "none";
  let overview: ConnectorsOverview | null = null, overviewError: string | null = null;
  try {
    const supabase = await createClient();
    const db = admin ? adminClient() : null;
    // everything this screen shows is independent: one round trip
    const [home, t, s, telSetting, calMine, telStatus, calStatus, o, i, ov] = await Promise.all([
      rpc<{ sync: Sync }>("admin_home"),
      supabase.from("wa_templates").select("name, language, audience, purpose, status").order("audience").order("name"),
      supabase.from("settings").select("value").eq("key", "live_mode").maybeSingle(),
      supabase.from("settings").select("value").eq("key", "telephony").maybeSingle(),
      rpc<CalendarMine>("calendar_mine").catch(() => null),
      admin ? rpc<Telephony>("telephony_status") : Promise.resolve(null),
      admin ? rpc<CalStatus>("calendar_status") : Promise.resolve([] as CalStatus),
      db ? db.from("outbox").select("id, kind, lead_id, status, attempts, answer, done_at").in("status", ["refused", "failed", "conflict"]).order("id", { ascending: false }).limit(30) : Promise.resolve({ data: null }),
      db ? db.from("inbox").select("envelope_id, type, lead_id, error, received_at").eq("status", "error").order("received_at", { ascending: false }).limit(30) : Promise.resolve({ data: null }),
      admin ? rpc<ConnectorsOverview>("connectors_overview").then((x) => ({ x, e: null }), (e: unknown) => ({ x: null, e: e instanceof Error ? e.message : String(e) })) : Promise.resolve({ x: null, e: null }),
    ]);
    overview = ov.x;
    overviewError = ov.e;
    sync = home.sync;
    templates = t.data ?? [];
    mine = calMine;
    telProvider = (telSetting.data?.value as Telephony["settings"] | undefined)?.provider ?? "none";
    tel = telStatus; cal = calStatus;
    live = (s.data?.value ?? {}) as typeof live;
    problems = (o.data ?? []) as typeof problems;
    inboxErrors = (i.data ?? []) as typeof inboxErrors;
  } catch (e) {
    return <Page title="Connectors"><SetupError error={e} /></Page>;
  }
  const waLive = liveMode() && !!live.whatsapp;
  return (
    <Page title="Connectors">
      {admin && (overview ? <Overview o={overview} /> : overviewError ? <div className="banner">The connector overview could not load: {overviewError}</div> : null)}
      {admin && <h2>Set-up</h2>}
      <div className="grid g3">
        <section className="card pad stack" style={{ gap: 8 }}>
          <div className="row between"><h2>B2B CRM link</h2><Status ok={b2bReady()}>{b2bReady() ? "Configured" : "Not configured"}</Status></div>
          <dl className="kv">
            <dt>Last event received</dt><dd>{when(sync.last_received_at)}</dd>
            <dt>Last batch sent</dt><dd>{when(sync.last_batch_at)}</dd>
            <dt>Waiting to send</dt><dd>{sync.queued}</dd>
            <dt>Refused or failed (7 days)</dt><dd>{sync.failed}</dd>
            <dt>Incoming with errors</dt><dd>{sync.inbox_errors}</dd>
          </dl>
          <p className="note">Hand-offs and lead changes arrive in real time. B2C activity goes back in one batch every 15 minutes; consent, opt-outs, erasure, partner routing, new students and counsellor assignments go at once.</p>
        </section>
        <section className="card pad stack" style={{ gap: 8 }}>
          <div className="row between"><h2>WhatsApp</h2><Status ok={waLive}>{waLive ? "Live" : "Test mode"}</Status></div>
          <p className="note">Messages go from the Eduwit B2C number through the WhatsApp Cloud API. In test mode they are recorded but not sent. Live needs both the server switch (LIVE_MODE) and Settings → live mode.</p>
          <div className="small">{templates.length} templates · {templates.filter((t) => t.status === "approved").length} approved by Meta</div>
        </section>
        <section className="card pad stack" style={{ gap: 8 }}>
          <div className="row between"><h2>Email</h2><Status ok={!!process.env.SMTP_HOST}>{process.env.SMTP_HOST ? "Sign-in codes ready" : "SMTP not set"}</Status></div>
          <p className="note">Sign-in codes and alerts go by SMTP through Google Workspace. Counsellors&apos; own emails to students go out from their mailbox (Gmail, domain-wide delegation) once Google is set up.</p>
        </section>
        <section className="card pad stack" style={{ gap: 8 }}>
          <div className="row between"><h2>Google Workspace</h2><Status ok={!!directoryConfig()}>{directoryConfig() ? "Teams sync on" : "Not set up"}</Status></div>
          <p className="note">Every night names, photos and job titles are read from Workspace; an account suspended there is deactivated here and its open leads are reassigned.</p>
        </section>
        <section className="card pad stack" style={{ gap: 8 }}>
          {(() => {
            const provider = tel?.settings.provider ?? telProvider;
            const on = provider === "exotel" ? !!exotelConfig() && liveMode() : provider === "mock";
            return <>
              <div className="row between"><h2>Telephony</h2><Status ok={on || provider === "none"}>{provider === "none" ? "Off: own phones" : provider === "mock" ? "Mock (rehearsal)" : on ? "Exotel live" : "Exotel not ready"}</Status></div>
              <p className="note">{provider === "none" ? "Counsellors dial from their own phones and log each call. Switch Settings → telephony → provider to exotel when the account is ready: calls are then bridged, recorded and logged by themselves."
                : `Calls ring the counsellor's phone, then the student, and log themselves; every call is recorded and kept ${tel?.settings.retention_days ?? 180} days. Test leads always use the mock.`}</p>
              {admin && tel && provider !== "none" && <dl className="kv small">
                <dt>Last event</dt><dd>{when(tel.last_event)}</dd><dt>Events, 24 h</dt><dd>{tel.events_24h}</dd><dt>Bridged calls, 7 days</dt><dd>{tel.bridged_7d}</dd>
                <dt>Recordings</dt><dd>{Object.entries(tel.recordings ?? {}).map(([k, v]) => `${v} ${k}`).join(" · ") || "none"}</dd>
                {provider === "exotel" && !exotelConfig() && <><dt>Missing</dt><dd>EXOTEL_SID, EXOTEL_API_KEY, EXOTEL_API_TOKEN, EXOTEL_WEBHOOK_KEY</dd></>}
                {provider === "exotel" && !liveMode() && <><dt>LIVE_MODE</dt><dd>off: no real call is placed</dd></>}
              </dl>}
              {admin && tel && tel.agents_without_phone.length > 0 && provider !== "none" && <p className="small">No mobile number in Teams: {tel.agents_without_phone.join(", ")}.</p>}
            </>;
          })()}
        </section>
        <section className="card pad stack" style={{ gap: 8 }}>
          <div className="row between"><h2>Google Calendar</h2><Status ok={!!googleSa()}>{googleSa() ? "Ready" : "Service account not set"}</Status></div>
          <CalendarToggle mine={mine} ready={!!googleSa()} />
          {admin && cal.some((c) => c.on) && <p className="small">On for {cal.filter((c) => c.on).map((c) => c.name).join(", ")}{cal.some((c) => c.error) ? `. Errors: ${cal.filter((c) => c.error).map((c) => `${c.name} (${c.error})`).join("; ")}` : ""}.</p>}
        </section>
        <section className="card pad stack" style={{ gap: 8 }}>
          <div className="row between"><h2>Phone alerts</h2><Status ok={!!pushConfig()}>{pushConfig() ? "Ready" : "Push keys not set"}</Status></div>
          <p className="note">Each person turns alerts on per device under Me → Availability and alerts. Reminders arrive 10 minutes before a follow-up.</p>
        </section>
      </div>
      <section className="stack">
        <div className="row between wrap"><h2>WhatsApp templates</h2>{admin && !overview && <ImportTemplatesButton />}</div>
        <div className="table-wrap"><table>
          <thead><tr><th>Name</th><th>For</th><th>Purpose</th><th>Language</th><th>Meta status</th></tr></thead>
          <tbody>{templates.map((t) => <tr key={`${t.name}-${t.language}`}><td className="mono">{t.name}</td><td>{t.audience}</td><td>{t.purpose ?? "—"}</td><td>{t.language}</td><td>{t.status}</td></tr>)}</tbody>
        </table></div>
      </section>
      {admin && tel && tel.unknown_calls.length > 0 && (
        <section className="stack">
          <h2>Missed calls from unknown numbers</h2>
          <div className="table-wrap"><table>
            <thead><tr><th>From</th><th>Status</th><th>When</th><th /></tr></thead>
            <tbody>{tel.unknown_calls.map((u) => <tr key={u.id}><td className="mono">{u.from_number}</td><td>{u.status}</td><td>{when(u.at)}</td><td><UnknownCallDone id={u.id} /></td></tr>)}</tbody>
          </table></div>
        </section>
      )}
      {admin && (problems.length > 0 || inboxErrors.length > 0) && (
        <section className="stack">
          <h2>Needs attention</h2>
          <div className="table-wrap"><table>
            <thead><tr><th>What</th><th>Lead</th><th>Status</th><th>Error</th><th>When</th></tr></thead>
            <tbody>
              {problems.map((p) => <tr key={`o${p.id}`}><td>Sent: {p.kind}</td><td>{p.lead_id ?? "—"}</td><td>{p.status} ({p.attempts})</td><td className="small">{p.answer?.error ?? "—"}</td><td>{when(p.done_at)}</td></tr>)}
              {inboxErrors.map((i) => <tr key={i.envelope_id}><td>Received: {i.type}</td><td>{i.lead_id ?? "—"}</td><td>error</td><td className="small">{i.error ?? "—"}</td><td>{when(i.received_at)}</td></tr>)}
            </tbody>
          </table></div>
        </section>
      )}
    </Page>
  );
}
