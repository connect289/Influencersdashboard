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
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Connectors" };

function Status({ ok, children }: { ok: boolean; children: React.ReactNode }) {
  return ok ? <span className="chip ok"><Check className="icon s" aria-hidden />{children}</span> : <span className="chip risk"><CircleAlert className="icon s" aria-hidden />{children}</span>;
}

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
  try {
    sync = (await rpc<{ sync: Sync }>("admin_home")).sync;
    const supabase = await createClient();
    const [t, s] = await Promise.all([
      supabase.from("wa_templates").select("name, language, audience, purpose, status").order("audience").order("name"),
      supabase.from("settings").select("value").eq("key", "live_mode").maybeSingle(),
    ]);
    templates = t.data ?? [];
    live = (s.data?.value ?? {}) as typeof live;
    if (admin) {
      const db = adminClient();
      const [o, i] = await Promise.all([
        db.from("outbox").select("id, kind, lead_id, status, attempts, answer, done_at").in("status", ["refused", "failed", "conflict"]).order("id", { ascending: false }).limit(30),
        db.from("inbox").select("envelope_id, type, lead_id, error, received_at").eq("status", "error").order("received_at", { ascending: false }).limit(30),
      ]);
      problems = (o.data ?? []) as typeof problems;
      inboxErrors = (i.data ?? []) as typeof inboxErrors;
    }
  } catch (e) {
    return <Page title="Connectors"><SetupError error={e} /></Page>;
  }
  const waLive = liveMode() && !!live.whatsapp;
  return (
    <Page title="Connectors">
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
          <div className="row between"><h2>Phone alerts</h2><Status ok={!!pushConfig()}>{pushConfig() ? "Ready" : "Push keys not set"}</Status></div>
          <p className="note">Each person turns alerts on per device under Me → Availability and alerts. Reminders arrive 10 minutes before a follow-up.</p>
        </section>
      </div>
      <section className="stack">
        <h2>WhatsApp templates</h2>
        <div className="table-wrap"><table>
          <thead><tr><th>Name</th><th>For</th><th>Purpose</th><th>Language</th><th>Meta status</th></tr></thead>
          <tbody>{templates.map((t) => <tr key={`${t.name}-${t.language}`}><td className="mono">{t.name}</td><td>{t.audience}</td><td>{t.purpose ?? "—"}</td><td>{t.language}</td><td>{t.status}</td></tr>)}</tbody>
        </table></div>
      </section>
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
