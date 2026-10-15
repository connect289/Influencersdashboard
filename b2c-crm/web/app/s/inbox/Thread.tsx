"use client";
import { useEffect, useState, useTransition } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { ArrowLeft, Clock, Lock, Send } from "lucide-react";
import { toast } from "sonner";
import { relative, when } from "@/lib/format";
import { waRead, waTemplate, waText } from "../actions";
import { snippetUsed, type Snippet } from "../snippet-actions";
import { MediaComposer, MediaLine, type AppChoice, type Media } from "./Media";

export type Compose = {
  phone: string | null;
  blocked: string | null;
  live: boolean;
  window_open: boolean | null;
  window_closes_at: string | null;
  templates: { id: number; name: string; language: string; purpose: string | null; status: string; preview: string }[];
  messages: { id: number; direction: "in" | "out"; kind: string; template_name: string | null; body: string | null; status: string; created_at: string; media?: Media; media_path?: string | null }[];
};

/**
 * One conversation. Free text, images, documents and brochures only inside the 24-hour window; otherwise an approved sales
 * template (Meta's rule). Files the student sends open by a short signed link and go onto the checklist in one tap.
 * Marketing reads it without a composer.
 */
export function Thread({ leadId, name, compose, snippets = [], vars = {}, readOnly, base = "/s/inbox", leadBase = "/s/leads", apps = [] }: {
  leadId: number; name: string | null; compose: Compose; snippets?: Snippet[]; vars?: Record<string, string | null | undefined>; readOnly?: boolean; base?: string; leadBase?: string; apps?: AppChoice[];
}) {
  const router = useRouter();
  const [pick, setPick] = useState<number | null>(null);
  const [text, setText] = useState("");
  const [busy, start] = useTransition();
  useEffect(() => { if (!readOnly) void waRead(leadId); }, [leadId, readOnly]);
  function insert(s: Snippet) {
    const filled = s.body.replace(/\{\{\s*(\w+)\s*\}\}/g, (m, k: string) => vars[k] ?? m);
    setText((t) => (t.trim() ? `${t.trimEnd()} ${filled}` : filled));
    void snippetUsed(s.id);
  }

  const send = (fn: () => Promise<{ ok: boolean; error?: string; notice?: string }>, after: () => void) =>
    start(async () => {
      const r = await fn();
      if (!r.ok) return void toast.error(r.error);
      toast.success(compose.live ? r.notice ?? "Queued." : "Queued. Test mode: nothing is sent to the student.");
      after();
      router.refresh();
    });

  return (
    <div className="card" style={{ display: "flex", flexDirection: "column", minHeight: 480 }}>
      <div className="s-head">
        <Link href={base} className="btn quiet sm only-phone" aria-label="Back"><ArrowLeft className="icon s" aria-hidden /></Link>
        <div className="grow"><b>{name ?? compose.phone}</b><div className="small muted mono">{compose.phone}</div></div>
        <Link className="btn quiet sm" href={`${leadBase}/${leadId}`}>Open lead</Link>
      </div>
      <div className="s-body thread" style={{ flex: 1 }}>
        {compose.messages.length === 0 && <p className="note">No messages yet.</p>}
        {compose.messages.map((m) => (
          <div key={m.id} className={`msg ${m.direction}`}>
            {m.template_name && <span className="tpl">Template · {m.template_name}</span>}
            {(m.kind === "media" || (m.media && (m.media.kind || m.media.id))) && <MediaLine messageId={m.id} direction={m.direction} media={m.media ?? null} stored={!!m.media_path} leadId={leadId} apps={apps} canWork={!readOnly} />}
            {m.body && <span style={{ whiteSpace: "pre-wrap" }}>{m.body}</span>}
            <span className="meta">{when(m.created_at)}{m.direction === "out" ? ` · ${m.status === "dry_run" ? "test mode, not sent" : m.status}` : ""}</span>
          </div>
        ))}
      </div>
      <div className="composer">
        {readOnly ? (
          <div className="window"><Lock className="icon s" aria-hidden />Read-only: the counsellor answers this conversation.</div>
        ) : compose.blocked ? (
          <div className="banner danger">Cannot message this student: {compose.blocked}.</div>
        ) : compose.window_open ? (
          <>
            <div className="window" style={{ color: "var(--green)" }}><Clock className="icon s" aria-hidden />Free text allowed, window closes {relative(compose.window_closes_at)}</div>
            {snippets.length > 0 && (
              <div className="hscroll" aria-label="Snippets">
                {snippets.map((s) => <button key={s.id} type="button" className="pill" onClick={() => insert(s)} title={s.body}>{s.title}</button>)}
                <Link className="pill" href="/s/me?tab=snippets" style={{ textDecoration: "none", color: "inherit" }}>Edit…</Link>
              </div>
            )}
            <form className="row" action={() => send(() => waText(leadId, text), () => setText(""))}>
              <MediaComposer leadId={leadId} disabled={busy} />
              <input className="input grow" value={text} onChange={(e) => setText(e.target.value)} placeholder="Type a message" maxLength={4096} aria-label="Message" />
              <button className="btn primary" type="submit" disabled={busy || !text.trim()} aria-label="Send"><Send className="icon s" aria-hidden /></button>
            </form>
          </>
        ) : (
          <>
            <div className="window" style={{ color: "var(--amber-ink)" }}><Lock className="icon s" aria-hidden />The 24-hour window is closed. Start with an approved sales template.</div>
            <div className="stack" style={{ gap: 6, maxHeight: 230, overflowY: "auto" }}>
              {compose.templates.length === 0 && <p className="note">No sales templates yet. The Admin adds them under Connectors.</p>}
              {compose.templates.map((t) => (
                <button key={t.id} type="button" className="tpl-card" aria-pressed={pick === t.id} onClick={() => setPick(t.id)}>
                  <span className="row between"><b>{t.purpose ?? "Template"}</b><code>{t.name} · {t.language}{t.status !== "approved" ? " · not approved yet" : ""}</code></span>
                  <span className="small">{t.preview}</span>
                </button>
              ))}
            </div>
            <button type="button" className="btn primary" disabled={busy || pick === null} onClick={() => pick !== null && send(() => waTemplate(leadId, pick), () => setPick(null))}>
              Send template
            </button>
          </>
        )}
      </div>
    </div>
  );
}
