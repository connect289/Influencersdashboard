"use client";
import { useState } from "react";
import { Bot } from "lucide-react";
import { wittyTranscript, type WittyMessage } from "@/app/s/actions";
import { when } from "@/lib/format";

/** Witty's conversation with the student, read-only (spec A: w2_messages is Witty's; the CRM never writes it). */
export function WittyTranscript({ leadId }: { leadId: number }) {
  const [rows, setRows] = useState<WittyMessage[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  function load(open: boolean) {
    if (!open || rows) return;
    wittyTranscript(leadId).then((r) => (r.ok ? setRows(r.data ?? []) : setError(r.error)));
  }

  return (
    <details className="panel more" onToggle={(e) => load((e.currentTarget as HTMLDetailsElement).open)}>
      <summary style={{ padding: 12 }}><Bot className="icon s" aria-hidden /> Witty&apos;s conversation <span className="small muted">read-only</span></summary>
      <div className="body">
        {error && <p className="error">{error}</p>}
        {!rows && !error && <p className="note">Loading…</p>}
        {rows && rows.length === 0 && <p className="note">Witty has not spoken to this student on any of their numbers.</p>}
        {rows && rows.length > 0 && (
          <div className="thread" style={{ maxHeight: 420, overflowY: "auto" }}>
            {rows.map((m) => (
              <div key={m.id} className={`msg ${m.direction === "in" ? "in" : "out"}`}>
                {m.direction !== "in" && <span className="tpl">Witty</span>}
                <span style={{ whiteSpace: "pre-wrap" }}>{m.content || (m.kind ? `[${m.kind}]` : "")}</span>
                <span className="meta">{when(m.at)}{m.direction !== "in" && m.sent === false ? " · not sent" : ""}</span>
              </div>
            ))}
          </div>
        )}
      </div>
    </details>
  );
}
