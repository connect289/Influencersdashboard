import { signedJwt, type GoogleSa } from "@/lib/gmail";
import { scrubPii } from "@/lib/scrub";

/**
 * Follow-ups in Google Calendar (spec B17, personal connector). One way, CRM → Calendar, through the service account's
 * domain-wide delegation (scope calendar.events) acting as each person. Events carry the task, the student's first
 * name, the programme and the lead link: never a phone number or an email.
 */
export type CalendarRow = {
  task_id: number; want: "upsert" | "remove"; event_id: string | null; etag: string | null; old_event_id: string | null; email: string | null; old_email: string | null;
  title: string; kind: string; due_at: string; note: string | null; lead_id: number; first_name: string | null; course: string | null;
};

const KIND: Record<string, string> = { call: "Call", whatsapp: "WhatsApp", email: "Email", document: "Documents", followup: "Follow up", qualify: "Qualify" };

export function eventBody(r: CalendarRow, site: string): Record<string, unknown> {
  const who = [r.first_name || "a student", r.course ? `(${r.course})` : ""].filter(Boolean).join(" ");
  const start = new Date(r.due_at);
  const end = new Date(start.getTime() + 15 * 60_000);
  const lines = [scrubPii(r.title), r.note ? scrubPii(r.note) : null, `Open the lead: ${site.replace(/\/+$/, "")}/s/leads/${r.lead_id}`].filter(Boolean);
  return {
    summary: `${KIND[r.kind] ?? "Follow up"}: ${scrubPii(who)}`.slice(0, 200),
    description: lines.join("\n\n").slice(0, 2000),
    start: { dateTime: start.toISOString(), timeZone: "Asia/Kolkata" },
    end: { dateTime: end.toISOString(), timeZone: "Asia/Kolkata" },
    reminders: { useDefault: false, overrides: [{ method: "popup", minutes: 10 }] },
    extendedProperties: { private: { b2cTaskId: String(r.task_id) } },
    source: { title: "Eduwit CRM", url: `${site.replace(/\/+$/, "")}/s/leads/${r.lead_id}` },
  };
}

const API = "https://www.googleapis.com/calendar/v3/calendars/primary/events";

export class CalendarClient {
  private tokens = new Map<string, string>();
  constructor(private sa: GoogleSa) {}

  private async token(email: string): Promise<string> {
    const hit = this.tokens.get(email);
    if (hit) return hit;
    const r = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, signal: AbortSignal.timeout(15_000),
      body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: signedJwt(this.sa, email, "https://www.googleapis.com/auth/calendar.events") }),
    });
    const t = (await r.json()) as { access_token?: string; error_description?: string; error?: string };
    if (!t.access_token) throw new Error(`Google refused calendar access for ${email}: ${t.error_description ?? t.error ?? r.status}`);
    this.tokens.set(email, t.access_token);
    return t.access_token;
  }

  async remove(email: string, eventId: string): Promise<void> {
    const r = await fetch(`${API}/${encodeURIComponent(eventId)}`, { method: "DELETE", headers: { authorization: `Bearer ${await this.token(email)}` }, signal: AbortSignal.timeout(15_000) });
    if (!r.ok && r.status !== 404 && r.status !== 410) throw new Error(`Calendar refused the removal (${r.status})`);
  }

  async upsert(email: string, eventId: string | null, body: Record<string, unknown>): Promise<{ id: string; etag: string }> {
    const auth = { authorization: `Bearer ${await this.token(email)}`, "content-type": "application/json" };
    if (eventId) {
      const r = await fetch(`${API}/${encodeURIComponent(eventId)}`, { method: "PATCH", headers: auth, body: JSON.stringify(body), signal: AbortSignal.timeout(15_000) });
      if (r.ok) { const e = (await r.json()) as { id: string; etag: string }; return { id: e.id, etag: e.etag }; }
      if (r.status !== 404 && r.status !== 410) throw new Error(`Calendar refused the update (${r.status})`);
    }
    const r = await fetch(API, { method: "POST", headers: auth, body: JSON.stringify(body), signal: AbortSignal.timeout(15_000) });
    if (!r.ok) throw new Error(`Calendar refused the event (${r.status})`);
    const e = (await r.json()) as { id: string; etag: string };
    return { id: e.id, etag: e.etag };
  }
}
