import Link from "next/link";
import { ArrowLeft, Lock } from "lucide-react";
import { when } from "@/lib/format";

export type UnmatchedThread = {
  phone: string;
  last_inbound_at: string | null;
  messages: { id: number; direction: "in" | "out"; kind: string; template_name: string | null; body: string | null; status: string; created_at: string; media: { type?: string; kind?: string } | null }[];
};

/**
 * A conversation from a number with no Spark lead yet (b2c.wa_unmatched_thread, Admin only): the B2B CRM has not routed
 * the new student here. Read-only: nothing can be sent until the lead is assigned in Spark.
 */
export function Unmatched({ thread, base }: { thread: UnmatchedThread; base: string }) {
  return (
    <div className="card" style={{ display: "flex", flexDirection: "column", minHeight: 480 }}>
      <div className="s-head">
        <Link href={base} className="btn quiet sm only-phone" aria-label="Back"><ArrowLeft className="icon s" aria-hidden /></Link>
        <div className="grow"><b className="mono">{thread.phone}</b><div className="small muted">New number, no lead in Spark yet</div></div>
      </div>
      <div className="s-body thread" style={{ flex: 1 }}>
        {thread.messages.length === 0 && <p className="note">No messages yet.</p>}
        {thread.messages.map((m) => (
          <div key={m.id} className={`msg ${m.direction}`}>
            {m.template_name && <span className="tpl">Template · {m.template_name}</span>}
            {m.media && <span className="small muted">[{m.media.type ?? m.media.kind ?? "file"}]</span>}
            {m.body && <span style={{ whiteSpace: "pre-wrap" }}>{m.body}</span>}
            <span className="meta">{when(m.created_at)}{m.direction === "out" ? ` · ${m.status === "dry_run" ? "test mode, not sent" : m.status}` : ""}</span>
          </div>
        ))}
      </div>
      <div className="composer">
        <div className="window"><Lock className="icon s" aria-hidden />New number — waiting for the CRM to route this lead; you can reply once it is assigned here.</div>
      </div>
    </div>
  );
}
