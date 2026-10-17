// What a notification looks like on each channel (spec 14): the staff-edited template for the event when there is
// one, else the built-in copy (the notification's own title and text). Variables come from the notification itself
// (name, title, body, link) and its data, limited to what the event's catalogue entry allows. WhatsApp needs an
// approved provider template; without one the WhatsApp copy is skipped. Pure.
import { allowedVars } from "./catalogue";
import { renderHtml, renderText, whatsappParams } from "./render";
import { escapeHtml, notificationLayout } from "./templates";
import type { EmailMessage, WhatsAppTemplateMessage } from "./types";

export interface NotificationFacts {
  event: string;
  title: string;
  body: string | null;
  /** In-app path, e.g. /creator/deals/…; made absolute with the site URL. */
  link: string | null;
  data: Readonly<Record<string, unknown>>;
}

export interface Template {
  subject: string | null;
  body: string;
  wa_template_name: string | null;
}

/** Template variables for a notification: common ones plus the event's own, as text. */
export function notificationVars(n: NotificationFacts, recipientName: string, siteUrl: string): Record<string, string> {
  const vars: Record<string, string> = {
    name: recipientName,
    title: n.title,
    body: n.body ?? "",
    link: absolute(n.link, siteUrl) ?? "",
  };
  for (const k of allowedVars(n.event)) {
    if (k in vars) continue;
    const v = n.data[k];
    if (typeof v === "string" || typeof v === "number") vars[k] = String(v);
  }
  return vars;
}

export function absolute(link: string | null, siteUrl: string): string | null {
  if (!link || !link.startsWith("/") || link.startsWith("//")) return null;
  return `${siteUrl.replace(/\/$/, "")}${link}`;
}

export function composeEmail(
  n: NotificationFacts,
  template: Template | null,
  recipientName: string,
  siteUrl: string,
): Omit<EmailMessage, "to"> {
  const vars = notificationVars(n, recipientName, siteUrl);
  const link = absolute(n.link, siteUrl);
  if (template) {
    const subject =
      renderText(template.subject ?? n.title, vars)
        .text.replace(/\s+/g, " ")
        .trim() || n.title;
    const text = renderText(template.body, vars).text;
    return {
      subject: subject.slice(0, 200),
      html: notificationLayout(subject, renderHtml(template.body, vars).text, link, "Open in the portal"),
      text: [text, link && !template.body.includes("{{link}}") ? link : ""].filter(Boolean).join("\n\n"),
    };
  }
  const body = n.body ?? "";
  return {
    subject: n.title.slice(0, 200),
    html: notificationLayout(
      n.title,
      body ? `<p>${escapeHtml(body).replace(/\n/g, "<br>")}</p>` : "",
      link,
      "Open in the portal",
    ),
    text: [body, link ?? ""].filter(Boolean).join("\n\n"),
  };
}

/** The WhatsApp template message, or null when the event has no approved template or the number is unusable. */
export function composeWhatsApp(
  n: NotificationFacts,
  template: Template | null,
  recipientName: string,
  phoneE164: string | null,
  siteUrl: string,
): WhatsAppTemplateMessage | null {
  if (!template?.wa_template_name) return null;
  const to = (phoneE164 ?? "").replace(/^\+/, "");
  if (!/^[1-9]\d{9,14}$/.test(to)) return null;
  return {
    to,
    template: template.wa_template_name,
    language: "en",
    params: whatsappParams(template.body, notificationVars(n, recipientName, siteUrl)),
  };
}
