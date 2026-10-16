/**
 * Pure helpers for the counsellor workspace (B8): merge fields, talk time, the call outcome's next step, neglect,
 * follow-up grouping. Unit-tested in workspace.test.ts.
 */
import { istDay } from "./format";

/** Every merge field a sales email may use (b2c.merge_values fills them from the lead, its best programme and the counsellor). */
export const MERGE_FIELDS = [
  "first_name", "programme", "university", "fee", "emi", "brochure_link", "counsellor_name", "counsellor_first_name", "counsellor_number", "followup_time",
] as const;
export type MergeValues = Partial<Record<(typeof MERGE_FIELDS)[number], string | null>>;

/** Older templates wrote {{counsellor}}: it means the counsellor's name. */
const ALIAS: Record<string, string> = { counsellor: "counsellor_name" };

/** Fills the merge fields it has values for; a field without a value stays as {{field}} so the composer can flag it. */
export function renderMerge(text: string, values: MergeValues): string {
  return text.replace(/\{\{\s*([a-z_]+)\s*\}\}/g, (m, k: string) => {
    const v = (values as Record<string, string | null | undefined>)[ALIAS[k] ?? k];
    return v ? String(v) : m;
  });
}

/** Minutes of talk from the time away (Call tapped → back in the app), rounded, at least 1, at most 600. */
export function talkMinutes(tappedAt: number, backAt: number): number {
  const ms = backAt - tappedAt;
  if (!Number.isFinite(ms) || ms <= 0) return 1;
  return Math.min(600, Math.max(1, Math.round(ms / 60000)));
}

export type Suggestion = { kind: string; in_minutes: number; note: string };

const MISSES = ["no_answer", "busy", "switched_off"];

/** The next step an outcome suggests (the same rule as b2c.call_suggestion): the third miss in 48 h suggests WhatsApp. */
export function suggestNext(outcome: string, recentMisses: number): Suggestion {
  if (MISSES.includes(outcome)) {
    return recentMisses >= 2
      ? { kind: "whatsapp", in_minutes: 30, note: "Three tries without an answer: send a WhatsApp template" }
      : { kind: "call", in_minutes: 180, note: "Retry the call" };
  }
  if (outcome === "call_back") return { kind: "call", in_minutes: 120, note: "Call back as asked" };
  if (outcome === "connected") return { kind: "call", in_minutes: 1440, note: "Follow-up call" };
  if (outcome === "wrong_number") return { kind: "whatsapp", in_minutes: 60, note: "Check the number on WhatsApp or ask for another" };
  return { kind: "call", in_minutes: 1440, note: "Follow up" };
}

/** "in 3 h", "tomorrow" for a suggestion's delay. */
export function inWords(minutes: number): string {
  if (minutes < 60) return `in ${minutes} min`;
  if (minutes < 1440) return `in ${Math.round(minutes / 60)} h`;
  return minutes === 1440 ? "tomorrow" : `in ${Math.round(minutes / 1440)} days`;
}

type Touch = { days_untouched?: number | null; last_activity_at?: string | null; assigned_at?: string | null; handed_off_at?: string | null };

/** Whole days since the lead was last worked (as leads_wide_v.days_untouched), or null when unknown. */
export function daysUntouched(l: Touch, now = new Date()): number | null {
  if (typeof l.days_untouched === "number") return l.days_untouched;
  const at = l.last_activity_at ?? l.assigned_at ?? l.handed_off_at;
  if (!at) return null;
  return Math.floor((now.getTime() - new Date(at).getTime()) / 864e5);
}

/** b2c.set_stage refuses a counsellor's move back with "moving back from X to Y needs the Admin". */
export const isMoveBackRefusal = (msg: string | null | undefined) => !!msg && /moving back .* needs the Admin/i.test(msg);

/** Rows grouped by their IST day, in the order given ("Tomorrow", "Sat 17 Oct"). */
export function groupByDay<T>(rows: T[], at: (r: T) => string | null | undefined, now = new Date()): { day: string; label: string; rows: T[] }[] {
  const out: { day: string; label: string; rows: T[] }[] = [];
  const today = istDay(now);
  const tomorrow = istDay(new Date(now.getTime() + 864e5));
  for (const r of rows) {
    const iso = at(r);
    const day = iso ? istDay(new Date(iso)) : "";
    let g = out.find((x) => x.day === day);
    if (!g) {
      const label = !iso ? "No date" : day === today ? "Today" : day === tomorrow ? "Tomorrow"
        : new Intl.DateTimeFormat("en-IN", { timeZone: "Asia/Kolkata", weekday: "short", day: "numeric", month: "short" }).format(new Date(iso)).replace(",", "");
      g = { day, label, rows: [] };
      out.push(g);
    }
    g.rows.push(r);
  }
  return out;
}

/** The first row still ahead of now: the next follow-up, highlighted in Due today. */
export function nextIndex<T>(rows: T[], at: (r: T) => string | null | undefined, now = new Date()): number {
  return rows.findIndex((r) => {
    const iso = at(r);
    return !!iso && new Date(iso).getTime() >= now.getTime();
  });
}

/** Alerts a person may also get on WhatsApp (settings staff_alerts.kinds), in words. */
export const WA_ALERT_LABEL: Record<string, string> = {
  reminder: "Follow-up reminders (10 minutes before)", overdue: "Overdue follow-ups", sla_breach: "First-contact SLA breached",
  escalation: "Escalations", assignment: "New lead assigned", neglect: "Lead untouched for 2 days", metric_alert: "Metric alerts", alert: "Other alerts",
};
export const WA_ALERT_DEFAULT = ["reminder", "overdue", "sla_breach", "escalation", "assignment", "neglect", "metric_alert"];

/** A brochure or other link in a template's attachments ([{name, url}]) as lines appended to an email. */
export function attachmentLines(attachments: unknown): string {
  if (!Array.isArray(attachments)) return "";
  const lines = attachments
    .map((a) => a as { name?: string; url?: string })
    .filter((a) => typeof a.url === "string" && /^https:\/\//.test(a.url))
    .map((a) => `${a.name ? `${a.name}: ` : ""}${a.url}`);
  return lines.length ? `\n\n${lines.join("\n")}` : "";
}
