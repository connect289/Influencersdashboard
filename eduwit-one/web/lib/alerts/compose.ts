import { z } from "zod";

// The words of an alert (spec §9): severity, app, check title, a short value and a link; the AI summary follows in
// the UI and does not hold the alert back. Values come from one.claim_deliveries(), already free of contact data.

export const incidentSchema = z.object({
  id: z.number(),
  check_id: z.string(),
  app: z.string(),
  severity: z.enum(["P1", "P2", "P3"]),
  title: z.string(),
  opened_at: z.string(),
  occurrences: z.number(),
  reopened_count: z.number(),
  subjects: z.array(z.string()),
  summary: z.string().nullable(),
  value: z.unknown().optional(),
  status: z.string().nullable().optional(),
  error: z.string().nullable().optional(),
});

export const deliverySchema = z.object({
  id: z.number(),
  recipient: z.string(),
  kind: z.enum(["alert", "escalation", "storm", "digest", "brief", "test"]),
  escalation_level: z.number(),
  attempts: z.number(),
  idempotency_key: z.string(),
  incident: incidentSchema.nullable(),
  digest: z
    .array(
      z.object({
        id: z.number(),
        check_id: z.string(),
        app: z.string(),
        title: z.string(),
        opened_at: z.string(),
        resolved: z.boolean(),
      }),
    )
    .nullable(),
  // The morning brief (0018): the text the AI wrote from the day's numbers.
  brief: z
    .object({
      id: z.number(),
      for_date: z.string(),
      body_md: z.string(),
      model: z.string().nullable(),
      // One saved view with a bad days value (edited by hand) must not make the brief unparseable (m3): it reads 30.
      views: z
        .array(
          z.object({
            name: z.string(),
            page: z.enum(["analytics", "marketing"]),
            days: z.coerce.number().int().min(1).max(365).catch(30),
          }),
        )
        .default([]),
    })
    .nullish(),
});

export type Delivery = z.infer<typeof deliverySchema>;
export type Composed = { subject: string; text: string; html: string };

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
const ist = (iso: string) =>
  new Intl.DateTimeFormat("en-IN", { timeZone: "Asia/Kolkata", dateStyle: "medium", timeStyle: "short" }).format(
    new Date(iso),
  );

/** A compact, bounded rendering of the check's value: enough to act on from a phone, never the whole object. */
export function shortValue(value: unknown, max = 400): string {
  if (value === undefined || value === null) return "";
  const text = typeof value === "string" ? value : JSON.stringify(value);
  return text.length > max ? `${text.slice(0, max)}…` : text;
}

function page(lines: string[], link: string, linkText: string): string {
  const body = lines.map((l) => `<p style="margin:0 0 8px">${esc(l)}</p>`).join("");
  return `<div style="font-family:system-ui,sans-serif;font-size:14px;color:#072E59">${body}<p><a href="${esc(link)}" style="color:#072E59;font-weight:600">${esc(linkText)}</a></p></div>`;
}

/** Markdown as plain lines: headings and emphasis marks dropped, runs of blank lines folded (the email is plain text). */
function plainLines(md: string, max = 120): string[] {
  const lines = md
    .split("\n")
    .map((l) =>
      l
        .replace(/^#{1,6}\s+/, "")
        .replace(/\*\*|__|`/g, "")
        .trimEnd(),
    )
    .filter((l, i, all) => l !== "" || (i > 0 && all[i - 1] !== ""));
  return lines.slice(0, max);
}

export function compose(d: Delivery, oneHost: string): Composed {
  if (d.kind === "brief") {
    const b = d.brief;
    if (!b) throw new Error(`delivery ${d.id} has no brief`);
    const link = `${oneHost}/brief/${b.id}`;
    const day = new Intl.DateTimeFormat("en-IN", { timeZone: "Asia/Kolkata", dateStyle: "medium" }).format(
      new Date(`${b.for_date}T12:00:00+05:30`),
    );
    const lines = plainLines(b.body_md).filter(Boolean);
    const note = "Written by the AI from the numbers on the brief's page; what is broken is decided by the checks.";
    // Saved views people asked to have emailed, as links (their numbers stay on the page).
    const views = b.views.map((v) => `${v.name}: ${oneHost}/${v.page}?days=${v.days}`);
    const viewLines = views.length ? ["", "Your saved views:", ...views.map((v) => `- ${v}`)] : [];
    return {
      subject: `[Eduwit One] Morning brief, ${day}`,
      text: [...plainLines(b.body_md), ...viewLines, "", `Open the brief: ${link}`, note].join("\n"),
      html: page([...lines, ...(views.length ? ["Your saved views:", ...views] : []), note], link, "Open the brief"),
    };
  }
  if (d.kind === "digest") {
    const items = d.digest ?? [];
    const lines = items.map((i) => `${i.check_id} (${i.app}): ${i.title}${i.resolved ? " (recovered)" : ""}`);
    const link = `${oneHost}/incidents?severity=P2`;
    return {
      subject: `[Eduwit One] ${items.length} P2 incidents today`,
      text: [`${items.length} P2 incidents opened today (IST):`, ...lines.map((l) => `- ${l}`), "", link].join("\n"),
      html: page([`${items.length} P2 incidents opened today (IST):`, ...lines], link, "Open the P2 list"),
    };
  }
  const i = d.incident;
  if (!i) throw new Error(`delivery ${d.id} has no incident`);
  const link = `${oneHost}/incidents/${i.id}`;
  const again =
    d.kind === "escalation"
      ? ` (reminder ${d.escalation_level}: not acknowledged)`
      : i.reopened_count > 0
        ? " (failing again)"
        : "";
  const storm = i.check_id === "ONE-STORM";
  const subject = `[${i.severity}] ${storm ? "Alert storm" : `${i.app}: ${i.title}`}${again} #${i.id}`;
  const lines = [
    `${i.severity} · ${i.app} · ${i.check_id}`,
    i.title,
    i.status && i.status !== "fail"
      ? `The check could not run (${i.status}): ${i.error ?? ""}`
      : `Value: ${shortValue(i.value)}`,
    i.subjects.length > 0 ? `Affected: ${i.subjects.slice(0, 10).join(", ")}` : "",
    `Opened ${ist(i.opened_at)} · seen ${i.occurrences} times`,
    // The AI's reading comes last and is marked as advice (m7): what is broken is decided by the lines above.
    i.summary ? `AI summary (advisory): ${i.summary}` : "",
  ].filter(Boolean);
  return {
    subject,
    text: [...lines, "", `Open and acknowledge: ${link}`].join("\n"),
    html: page(lines, link, "Open and acknowledge"),
  };
}
