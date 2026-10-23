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

export function compose(d: Delivery, oneHost: string): Composed {
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
    i.summary ? `Summary: ${i.summary}` : "",
  ].filter(Boolean);
  return {
    subject,
    text: [...lines, "", `Open and acknowledge: ${link}`].join("\n"),
    html: page(lines, link, "Open and acknowledge"),
  };
}
