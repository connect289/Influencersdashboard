/**
 * Support tickets (b31): the email each message makes for the developer, and how the developer's emailed answer is read
 * back (the ticket number in the subject, an optional "Status:" line). Pure, unit-tested in support.test.ts.
 */
export const KIND_LABEL: Record<string, string> = {
  bug: "Something is not working", feature: "A new feature or change", phone: "Change my phone number", access: "Sign-in or access", data: "Wrong data", other: "Something else",
};
export const STATUS_LABEL: Record<string, string> = { open: "Open", in_progress: "In progress", waiting: "Waiting for you", fixed: "Fixed", closed: "Closed" };
export const ROLE_WORD: Record<string, string> = { admin: "Admin", marketing: "Marketing", counsellor: "Counsellor", sales_head: "Sales manager" };

export type MailRow = {
  message_id: number; ticket_id: number; number: string; subject: string; kind: string; priority: string; status: string; page: string | null; first: boolean;
  body: string; urls: string[]; attachments: { path: string; name: string; type: string; size: number }[]; status_to: string | null;
  author: string; author_email: string | null; author_role: string | null; by: string; by_email: string; by_role: string; developer_emails: string[]; mailbox: string | null;
};

export function supportEmail(r: MailRow, site: string, token: string): { subject: string; text: string } {
  const base = site.replace(/\/+$/, "");
  const head = r.first
    ? `New ticket from ${r.by} (${ROLE_WORD[r.by_role] ?? r.by_role}, ${r.by_email})\nAbout: ${KIND_LABEL[r.kind] ?? r.kind}${r.priority === "urgent" ? " · URGENT" : ""}${r.page ? `\nScreen: ${base}${r.page.startsWith("/") ? r.page : `/${r.page}`}` : ""}`
    : r.status_to === "closed" ? `${r.author} closed the ticket.` : r.status_to === "open" ? `${r.author} reopened the ticket.` : `${r.author} wrote:`;
  const lines = [
    head, "", r.body,
    ...(r.urls.length ? ["", "Links:", ...r.urls.map((u) => `- ${u}`)] : []),
    ...(r.attachments.length ? ["", `Screenshots attached: ${r.attachments.map((a) => a.name).join(", ")}`] : []),
    "", "—",
    r.mailbox ? "Reply to this email to answer: your reply appears on the ticket. To change the status put one line in your reply: Status: in progress / need info / fixed / closed." : "",
    `Or answer here: ${base}/support/r/${token}`,
  ].filter((l, i, a) => !(l === "" && a[i - 1] === ""));
  return { subject: `[${r.number}] ${r.subject}${r.priority === "urgent" && r.first ? " (urgent)" : ""}`, text: lines.join("\n") };
}

/** The ticket an emailed answer belongs to: [SUP-0042] anywhere in the subject. */
export function ticketFromSubject(subject: string): number | null {
  const m = /\[SUP-(\d{1,9})\]/i.exec(subject);
  return m ? Number(m[1]) : null;
}

/** A "Status: …" line in the answer sets the status; the line itself is taken out of the text. */
export function statusFromReply(text: string): { status: string | null; body: string } {
  const WORDS: [RegExp, string][] = [[/^(in progress|working( on it)?|started)$/i, "in_progress"], [/^(need info|need more info|waiting|question)$/i, "waiting"],
    [/^(fixed|done|resolved|deployed)$/i, "fixed"], [/^(closed?|won'?t fix|not a bug|duplicate)$/i, "closed"]];
  let status: string | null = null;
  const kept = text.split("\n").filter((l) => {
    const m = /^\s*status\s*[:=-]\s*(.+?)\s*\.?\s*$/i.exec(l);
    if (!m || status) return true;
    const hit = WORDS.find(([re]) => re.test(m[1]!));
    if (!hit) return true;
    status = hit[1];
    return false;
  });
  return { status, body: kept.join("\n").trim() };
}

/** Screenshots people may attach: images and PDFs, 4 MB each, 4 files and 4 MB in all (the server's request limit). */
export const ATTACH = { types: ["image/png", "image/jpeg", "image/webp", "image/gif", "application/pdf"], each: 4 * 1024 * 1024, files: 4, total: 4 * 1024 * 1024 };
export function attachmentProblem(files: { name: string; type: string; size: number }[]): string | null {
  if (files.length > ATTACH.files) return `At most ${ATTACH.files} files.`;
  if (files.some((f) => !ATTACH.types.includes(f.type))) return "Screenshots (PNG, JPEG, WebP, GIF) or PDFs only.";
  if (files.reduce((a, f) => a + f.size, 0) > ATTACH.total) return "The files come to more than 4 MB: send fewer or smaller ones.";
  return null;
}
export const extFor = (type: string) => ({ "image/png": "png", "image/jpeg": "jpg", "image/webp": "webp", "image/gif": "gif", "application/pdf": "pdf" } as Record<string, string>)[type] ?? "bin";
