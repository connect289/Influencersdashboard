"use client";
import { useState, useTransition } from "react";
import { Play } from "lucide-react";
import { toast } from "sonner";
import { recordingLink } from "@/app/s/call-actions";
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
                {t.kind === "call" && t.meta?.bridged === true && typeof t.meta.call_id === "number" && <RecordingButton callId={t.meta.call_id} />}
                {t.actor && <div className="small muted">{t.actor}</div>}
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

/** Plays a bridged call's recording: a 5-minute signed link, opened only for someone who may see the lead (logged). */
function RecordingButton({ callId }: { callId: number }) {
  const [src, setSrc] = useState<string | null>(null);
  const [busy, start] = useTransition();
  if (src) return <audio controls autoPlay src={src} style={{ width: "100%", maxWidth: 360, marginTop: 4 }} />;
  return (
    <button type="button" className="btn quiet sm" disabled={busy} onClick={() => start(async () => {
      const r = await recordingLink(callId);
      if (!r.ok || !r.data) return void toast.error(r.ok ? "No recording." : r.error);
      setSrc(r.data);
    })}><Play className="icon s" aria-hidden />Recording</button>
  );
}
