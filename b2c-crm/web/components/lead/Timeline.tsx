"use client";
import { useState } from "react";
import { when } from "@/lib/format";
import { TIMELINE_KIND_LABEL } from "@/lib/labels";
import type { TimelineItem } from "@/lib/types";

const GROUPS: { key: string; label: string; kinds: string[] | null }[] = [
  { key: "all", label: "All", kinds: null },
  { key: "calls", label: "Calls", kinds: ["call"] },
  { key: "messages", label: "WhatsApp and email", kinds: ["whatsapp", "email", "programme_shared"] },
  { key: "notes", label: "Notes", kinds: ["note", "coaching"] },
  { key: "stage", label: "Stage and assignment", kinds: ["stage", "assignment", "handoff", "reenquiry", "reengaged"] },
  { key: "records", label: "Changes and documents", kinds: ["contact", "correction", "application", "enrollment", "system"] },
];

/** The lead's timeline with a filter by type (spec B8.5). */
export function Timeline({ items, children }: { items: TimelineItem[]; children?: React.ReactNode }) {
  const [group, setGroup] = useState("all");
  const kinds = GROUPS.find((g) => g.key === group)?.kinds ?? null;
  const shown = kinds ? items.filter((t) => kinds.includes(t.kind)) : items;
  return (
    <section className="panel">
      <header><h3>Timeline</h3><span className="small muted">{shown.length} of {items.length}</span></header>
      <div className="body">
        {children}
        <div className="pills" role="group" aria-label="Show" style={{ margin: "8px 0" }}>
          {GROUPS.map((g) => (
            <button key={g.key} type="button" className="pill" aria-pressed={group === g.key} onClick={() => setGroup(g.key)}>{g.label}</button>
          ))}
        </div>
        <div className="tl">
          {shown.length === 0 && <p className="note">Nothing here yet.</p>}
          {shown.map((t) => (
            <div key={t.id} className="tl-item">
              <time dateTime={t.at}>{when(t.at).replace(/^Today /, "")}</time>
              <div>
                <div className="tl-kind">{TIMELINE_KIND_LABEL[t.kind] ?? t.kind}{t.direction === "in" ? " · in" : ""}{t.internal ? " · coaching (Admin only)" : ""}</div>
                <div style={{ whiteSpace: "pre-wrap" }}>{t.body}</div>
                {t.actor && <div className="small muted">{t.actor}</div>}
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
