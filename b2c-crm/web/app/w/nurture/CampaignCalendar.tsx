import Link from "next/link";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { rpc } from "@/lib/data";

type Cal = {
  month: string;
  campaigns: { id: number; name: string; channel: "whatsapp" | "email"; status: string; recurring: string | null; day: string; at: string; segment: string | null; test_only: boolean }[];
  sent: Record<string, number>;
};

const DOW = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

/** One month of campaigns and automated sends (spec B9.3), so Marketing sees what lands on which day before scheduling more. */
export async function CampaignCalendar({ month }: { month?: string }) {
  const m = /^\d{4}-\d{2}$/.test(month ?? "") ? `${month}-01` : null;
  const cal = await rpc<Cal>("campaign_calendar", { p_month: m });
  const first = new Date(`${cal.month}T00:00:00+05:30`);
  const y = first.getUTCFullYear();
  const mo = first.getUTCMonth();
  const days = new Date(Date.UTC(y, mo + 1, 0)).getUTCDate();
  const lead = (new Date(Date.UTC(y, mo, 1)).getUTCDay() + 6) % 7; // Monday first
  const prev = new Date(Date.UTC(y, mo - 1, 1)).toISOString().slice(0, 7);
  const next = new Date(Date.UTC(y, mo + 1, 1)).toISOString().slice(0, 7);
  const title = first.toLocaleDateString("en-IN", { month: "long", year: "numeric", timeZone: "Asia/Kolkata" });
  const today = new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Kolkata" });
  const byDay = new Map<string, Cal["campaigns"]>();
  for (const c of cal.campaigns) byDay.set(c.day, [...(byDay.get(c.day) ?? []), c]);
  const cells: (number | null)[] = [...Array<null>(lead).fill(null), ...Array.from({ length: days }, (_, i) => i + 1)];
  while (cells.length % 7) cells.push(null);
  return (
    <section className="panel">
      <header>
        <h3>Calendar · {title}</h3>
        <span className="row" style={{ gap: 4 }}>
          <Link className="btn quiet sm icon-only" href={`/w/nurture?tab=campaigns&m=${prev}`} aria-label="Previous month"><ChevronLeft className="icon s" aria-hidden /></Link>
          <Link className="btn quiet sm icon-only" href={`/w/nurture?tab=campaigns&m=${next}`} aria-label="Next month"><ChevronRight className="icon s" aria-hidden /></Link>
        </span>
      </header>
      <div className="body">
        <div className="cal-grid">
          {DOW.map((d) => <div key={d} className="cal-dow">{d}</div>)}
          {cells.map((d, i) => {
            if (!d) return <div key={`e${i}`} className="cal-cell empty" />;
            const key = `${cal.month.slice(0, 8)}${String(d).padStart(2, "0")}`;
            const cs = byDay.get(key) ?? [];
            const n = cal.sent[key] ?? 0;
            return (
              <div key={key} className={`cal-cell${key === today ? " today" : ""}`}>
                <div className="cal-day">{d}{n > 0 && <span className="small muted"> · {n} sent</span>}</div>
                {cs.map((c) => (
                  <span key={c.id} className={`cal-item ${c.channel}${c.status === "done" ? " done" : ""}`} title={`${c.name} · ${c.segment ?? "no segment"} · ${c.status}`}>
                    {c.name}{c.recurring ? ` ↻` : ""}{c.test_only ? " (test)" : ""}
                  </span>
                ))}
              </div>
            );
          })}
        </div>
        <p className="small muted">A campaign shows on its scheduled day (or the day it started); "sent" counts the automated WhatsApp and email messages of journeys and campaigns that day. Recurring campaigns show once, on their next run.</p>
      </div>
    </section>
  );
}
