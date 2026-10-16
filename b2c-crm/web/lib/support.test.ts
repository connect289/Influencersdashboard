import { describe, expect, it } from "vitest";
import { attachmentProblem, statusFromReply, supportEmail, ticketFromSubject, type MailRow } from "./support";
import { readSupportToken, supportToken } from "./support-token";

const KEY = "k".repeat(40);
const row: MailRow = { message_id: 1, ticket_id: 42, number: "SUP-0042", subject: "Follow-ups page is blank", kind: "bug", priority: "urgent", status: "open", page: "/s/followups", first: true,
  body: "Since this morning the page shows nothing.", urls: ["https://crm.eduwit.in/s/followups"], attachments: [{ path: "tickets/42/x.png", name: "screen.png", type: "image/png", size: 10 }],
  status_to: null, author: "Priya", author_email: "priya@eduwit.in", author_role: "counsellor", by: "Priya", by_email: "priya@eduwit.in", by_role: "counsellor",
  developer_emails: ["dev@example.com"], mailbox: "support@eduwit.in" };

describe("support tickets", () => {
  it("writes the developer's email with the ticket number, who, what, links, screenshots and both ways to answer", () => {
    const m = supportEmail(row, "https://crm.eduwit.in/", "TOKEN");
    expect(m.subject).toBe("[SUP-0042] Follow-ups page is blank (urgent)");
    expect(m.text).toContain("New ticket from Priya (Counsellor, priya@eduwit.in)");
    expect(m.text).toContain("Screen: https://crm.eduwit.in/s/followups");
    expect(m.text).toContain("- https://crm.eduwit.in/s/followups");
    expect(m.text).toContain("Screenshots attached: screen.png");
    expect(m.text).toContain("Reply to this email");
    expect(m.text).toContain("https://crm.eduwit.in/support/r/TOKEN");
    expect(supportEmail({ ...row, first: false, mailbox: null, author: "Priya", status_to: "closed" }, "https://x", "T").text).not.toContain("Reply to this email");
  });
  it("reads the answer back", () => {
    expect(ticketFromSubject("Re: [SUP-0042] Follow-ups page is blank")).toBe(42);
    expect(ticketFromSubject("Hello")).toBeNull();
    expect(statusFromReply("Status: fixed\nDeployed the fix, please check.")).toEqual({ status: "fixed", body: "Deployed the fix, please check." });
    expect(statusFromReply("Can you send the browser version?\nstatus - need info")).toEqual({ status: "waiting", body: "Can you send the browser version?" });
    expect(statusFromReply("Status: who knows")).toEqual({ status: null, body: "Status: who knows" });
  });
  it("signs the developer's link", () => {
    expect(readSupportToken(supportToken(42, KEY), KEY)).toBe(42);
    expect(readSupportToken(supportToken(42, KEY) + "x", KEY)).toBeNull();
    expect(readSupportToken(supportToken(42, KEY), "z".repeat(40))).toBeNull();
  });
  it("limits screenshots", () => {
    expect(attachmentProblem([{ name: "a.png", type: "image/png", size: 1000 }])).toBeNull();
    expect(attachmentProblem([{ name: "a.exe", type: "application/x-msdownload", size: 10 }])).toMatch(/only/);
    expect(attachmentProblem(Array.from({ length: 5 }, () => ({ name: "a.png", type: "image/png", size: 1 })))).toMatch(/At most/);
    expect(attachmentProblem([{ name: "a.png", type: "image/png", size: 5 * 1024 * 1024 }])).toMatch(/more than 4 MB/);
  });
});
