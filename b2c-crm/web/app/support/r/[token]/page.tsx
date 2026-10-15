import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { adminClient } from "@/lib/supabase/admin";
import { KIND_LABEL, ROLE_WORD, STATUS_LABEL } from "@/lib/support";
import { readSupportToken } from "@/lib/support-token";
import { DeveloperForm } from "./DeveloperForm";

export const metadata: Metadata = { title: "Support ticket", robots: { index: false, follow: false } };
export const dynamic = "force-dynamic";

type T = { id: number; number: string; kind: string; priority: string; subject: string; status: string; page: string | null; created_at: string; by: string; by_role: string;
  messages: { id: number; author_kind: string; author: string; body: string; urls: string[]; attachments: { path: string; name: string; type: string }[]; status_to: string | null; created_at: string }[] };

const fmt = (iso: string) => new Intl.DateTimeFormat("en-IN", { timeZone: "Asia/Kolkata", dateStyle: "medium", timeStyle: "short" }).format(new Date(iso));

/** The developer's view of one ticket, from the signed link in the email: the thread, the screenshots, and the answer form. */
export default async function DeveloperTicket({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const id = readSupportToken(token);
  if (!id) notFound();
  const db = adminClient();
  const { data, error } = await db.rpc("support_for_developer", { p_ticket: id });
  if (error || !data) notFound();
  const t = data as T;
  const links = new Map<string, string>();
  for (const m of t.messages) for (const a of m.attachments) {
    const s = await db.storage.from("b2c-support").createSignedUrl(a.path, 3600);
    if (s.data) links.set(a.path, s.data.signedUrl);
  }
  return (
    <main className="content" style={{ maxWidth: 820, margin: "0 auto", padding: 16 }}>
      <div className="stack">
        <div className="stack" style={{ gap: 4 }}>
          <span className="eyebrow">Eduwit CRM support · {t.number}</span>
          <h1>{t.subject}</h1>
          <p className="small muted">{KIND_LABEL[t.kind] ?? t.kind}{t.priority === "urgent" ? " · URGENT" : ""} · raised by {t.by} ({ROLE_WORD[t.by_role] ?? t.by_role}) on {fmt(t.created_at)}{t.page ? ` · screen ${t.page}` : ""} · now <b>{STATUS_LABEL[t.status] ?? t.status}</b></p>
        </div>
        {t.messages.map((m) => (
          <article key={m.id} className="card pad stack" style={{ gap: 6, borderLeft: m.author_kind === "developer" ? "3px solid var(--amber)" : undefined }}>
            <div className="small"><b>{m.author_kind === "developer" ? "Developer" : m.author}</b> <span className="muted">{fmt(m.created_at)}</span>{m.status_to ? ` → ${STATUS_LABEL[m.status_to] ?? m.status_to}` : ""}</div>
            {m.body && <p style={{ whiteSpace: "pre-wrap" }}>{m.body}</p>}
            {m.urls.length > 0 && <ul className="small" style={{ margin: 0, paddingLeft: 18 }}>{m.urls.map((u) => <li key={u}><a href={u} target="_blank" rel="noopener noreferrer">{u}</a></li>)}</ul>}
            {m.attachments.length > 0 && <div className="row wrap" style={{ gap: 8 }}>{m.attachments.map((a) => links.get(a.path) && (
              <a key={a.path} href={links.get(a.path)} target="_blank" rel="noopener noreferrer">
                {a.type.startsWith("image/") ? <img src={links.get(a.path)} alt={a.name} style={{ maxWidth: 260, maxHeight: 200, borderRadius: 6, border: "1px solid var(--line)" }} /> : a.name}
              </a>))}</div>}
          </article>
        ))}
        <DeveloperForm token={token} status={t.status} />
        <p className="note">This page is reached only through the link in the ticket email; anyone with the link can answer this one ticket. Screenshot links last an hour: reload for fresh ones.</p>
      </div>
    </main>
  );
}
