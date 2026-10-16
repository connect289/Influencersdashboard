import { plainCodes } from "@/lib/labels";
import Link from "next/link";
import { Bell } from "lucide-react";
import { rpc } from "@/lib/data";
import { when } from "@/lib/format";
import type { Notification } from "@/lib/types";
import { MarkRead } from "./MarkRead";

/** In-app alerts: new assignment, re-engaged hot lead, SLA, reminders, replies, enrolment checks. */
export async function Notifications({ limit = 15, all = false }: { limit?: number; all?: boolean } = {}) {
  const n = await rpc<{ unread: number; items: Notification[] }>("notifications_mine", { p_limit: limit }).catch(() => ({ unread: 0, items: [] as Notification[] }));
  return (
    <section className="panel">
      <header>
        <h3 className="row" style={{ gap: 6 }}><Bell className="icon s" aria-hidden />Alerts{n.unread ? <span className="chip hot">{n.unread}</span> : null}</h3>
        <span className="row" style={{ gap: 4 }}>{n.unread > 0 && <MarkRead />}{!all && <Link className="btn quiet sm" href="/s/alerts">All</Link>}</span>
      </header>
      <div className="body">
        {n.items.length === 0 ? <p className="note">No alerts yet.</p> : (
          <div className="tl">
            {n.items.map((x) => (
              <div key={x.id} className="tl-item" style={{ gridTemplateColumns: "1fr" }}>
                <div>
                  <div className="row between">
                    {x.link ? <Link href={x.link} style={{ fontWeight: x.read_at ? 500 : 650 }}>{x.title}</Link> : <b>{x.title}</b>}
                    <time>{when(x.created_at)}</time>
                  </div>
                  {x.body && <div className="small muted">{plainCodes(x.body)}</div>}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </section>
  );
}
