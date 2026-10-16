import { describe, expect, it } from "vitest";
import { eventBody, type CalendarRow } from "./calendar";

const row: CalendarRow = { task_id: 7, want: "upsert", event_id: null, etag: null, old_event_id: null, email: "rohan@eduwit.in", old_email: null,
  title: "Discuss fees", kind: "call", due_at: "2026-10-16T05:30:00.000Z", note: "parent asked about EMI; call +91 98765 43210 or asha@gmail.com", lead_id: 900061,
  first_name: "Kiran", course: "MBA" };

describe("calendar events", () => {
  it("names the task and the student by first name, with the lead link and a 10-minute reminder", () => {
    const b = eventBody(row, "https://crm.eduwit.in/");
    expect(b.summary).toBe("Call: Kiran (MBA)");
    expect(String(b.description)).toContain("https://crm.eduwit.in/s/leads/900061");
    expect(b.start).toEqual({ dateTime: "2026-10-16T05:30:00.000Z", timeZone: "Asia/Kolkata" });
    expect(b.end).toEqual({ dateTime: "2026-10-16T05:45:00.000Z", timeZone: "Asia/Kolkata" });
    expect(b.reminders).toEqual({ useDefault: false, overrides: [{ method: "popup", minutes: 10 }] });
  });
  it("never carries a phone number or an email", () => {
    const text = JSON.stringify(eventBody(row, "https://crm.eduwit.in"));
    expect(text).not.toMatch(/98765|43210|@gmail|asha@/);
  });
});
