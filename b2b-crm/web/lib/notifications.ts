import { z } from "zod";

/** Student notifications (spec B9): the message sent once a partner has accepted the lead. */

export const VARIABLES = ["student_first_name", "programme_label", "partner_display_name", "expected_contact_window", "eduwit_support_contact"] as const;

export const VARIABLE_LABEL: Record<(typeof VARIABLES)[number], string> = {
  student_first_name: "Student's first name",
  programme_label: "Programme",
  partner_display_name: "Partner's name",
  expected_contact_window: "When the partner will call",
  eduwit_support_contact: "Eduwit support contact",
};

export const CHANNEL_LABEL: Record<"whatsapp" | "email", string> = { whatsapp: "WhatsApp", email: "Email" };
export const LANGUAGE_LABEL: Record<"en" | "hi", string> = { en: "English", hi: "Hindi / Hinglish" };
export const KIND_LABEL: Record<string, string> = { accepted: "Partner assigned", reroute_update: "New counsellor" };

export const STATUS_LABEL: Record<string, string> = {
  scheduled: "Scheduled",
  sending: "Sending",
  sent: "Sent",
  delivered: "Delivered",
  read: "Read",
  failed: "Failed",
  cancelled: "Cancelled",
  skipped: "Not sent",
};

export const STATUS_TONE: Record<string, "success" | "warning" | "danger" | "neutral" | "info"> = {
  scheduled: "info",
  sending: "info",
  sent: "success",
  delivered: "success",
  read: "success",
  failed: "danger",
  cancelled: "neutral",
  skipped: "neutral",
};

export type Template = {
  id: number;
  kind: string;
  channel: "whatsapp" | "email";
  language: "en" | "hi";
  subject: string | null;
  body: string;
  wa_template: string | null;
  wa_language: string | null;
  status: "draft" | "active";
  version: number;
  updated_at: string;
};

export type LogRow = {
  id: number;
  lead_id: number;
  lead_name: string | null;
  partner_name: string | null;
  channel: "whatsapp" | "email";
  kind: string;
  language: string;
  status: string;
  error: string | null;
  recipient: string;
  scheduled_for: string | null;
  sent_at: string | null;
  created_at: string;
};

export type NotificationsOverview = {
  settings: {
    quiet_start: string | null;
    quiet_end: string | null;
    support_contact: string | null;
    unsubscribe_url: string | null;
    whatsapp: { provider?: string; phone_number_id?: string | null; api_version?: string | null; base_url?: string; has_token: boolean };
    email: { provider?: "resend" | "brevo"; from_email?: string | null; from_name?: string | null; reply_to?: string | null; base_url?: string; has_key: boolean };
  };
  version: number;
  switches: { whatsapp: boolean; email: boolean };
  templates: Template[];
  partners: { id: number; name: string; notify_enabled: boolean }[];
  counts: Record<string, number>;
  log: LogRow[];
};

export type Preview = { subject: string | null; text: string; html: string | null; variables: Record<string, string> };

/** What still stops a channel from sending, in the order the Admin should fix it. */
export function channelBlockers(o: NotificationsOverview, channel: "whatsapp" | "email"): string[] {
  const s = o.settings;
  const out: string[] = [];
  if (!s.support_contact) out.push("Add Eduwit's support contact in Providers.");
  if (channel === "whatsapp") {
    if (!s.whatsapp.phone_number_id) out.push("Add the WhatsApp phone number ID.");
    if (!s.whatsapp.has_token) out.push("Store the WhatsApp access token.");
  } else {
    if (!s.email.from_email) out.push("Add the sender address.");
    if (!s.email.has_key) out.push("Store the email API key.");
  }
  if (!o.templates.some((t) => t.channel === channel && t.kind === "accepted" && t.language === "en" && t.status === "active")) {
    out.push(`Activate the English ${CHANNEL_LABEL[channel]} template.`);
  }
  return out;
}

/** Unknown {{variables}} in a template (the database refuses them too). */
export function unknownVariables(text: string): string[] {
  const found = [...text.matchAll(/\{\{([^}]*)\}\}/g)].map((m) => (m[1] ?? "").trim());
  return [...new Set(found.filter((v) => !(VARIABLES as readonly string[]).includes(v)))];
}

/** Renders a template the way b2b.render_template does: known variables replaced, unknown ones left as written. */
export function renderTemplate(body: string, vars: Record<string, string | null | undefined>): string {
  return body.replace(/\{\{([^}]*)\}\}/g, (all, k: string) => {
    const v = vars[k.trim()];
    return v === undefined || v === null ? all : v;
  });
}

const time = z.string().trim().regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Use HH:MM, e.g. 08:00");
const optionalEmail = z.string().trim().toLowerCase().max(200).refine((v) => v === "" || /^[^@\s]+@[^@\s]+\.[a-z]{2,}$/.test(v), "Enter an email address");

export const SettingsSchema = z
  .object({
    quiet_start: time,
    quiet_end: time,
    support_contact: z.string().trim().min(5, "Give a staffed phone number or email").max(120),
    unsubscribe_url: z.string().trim().max(300).refine((v) => v === "" || /^https:\/\//.test(v), "Use an https:// link, or leave it empty"),
    wa_phone_number_id: z.string().trim().refine((v) => v === "" || /^\d{6,30}$/.test(v), "Digits only, as Meta shows it"),
    wa_api_version: z.string().trim().regex(/^v\d{1,3}\.\d$/, "e.g. v21.0"),
    wa_token: z.string().max(4000),
    email_provider: z.enum(["resend", "brevo"]),
    email_from: optionalEmail,
    email_from_name: z.string().trim().max(80),
    email_reply_to: optionalEmail,
    email_api_key: z.string().max(4000),
    reason: z.string().trim().min(3, "Say why, for the audit log").max(300),
  })
  .refine((v) => v.quiet_start < v.quiet_end, { path: ["quiet_end"], message: "The end must be after the start" });

export type SettingsInput = z.infer<typeof SettingsSchema>;

/** The payload b2b.notification_settings_save expects. An empty secret keeps the stored one. */
export function settingsPayload(v: SettingsInput) {
  return {
    quiet_start: v.quiet_start,
    quiet_end: v.quiet_end,
    support_contact: v.support_contact,
    unsubscribe_url: v.unsubscribe_url,
    whatsapp: { phone_number_id: v.wa_phone_number_id, api_version: v.wa_api_version, token: v.wa_token.trim() },
    email: { provider: v.email_provider, from_email: v.email_from, from_name: v.email_from_name, reply_to: v.email_reply_to, api_key: v.email_api_key.trim() },
  };
}

export const TemplateSchema = z
  .object({
    channel: z.enum(["whatsapp", "email"]),
    subject: z.string().trim().max(150),
    body: z.string().trim().min(20, "Write at least 20 characters").max(4000),
    wa_template: z.string().trim().max(120).refine((v) => v === "" || /^[a-z0-9_]+$/.test(v), "Lowercase letters, digits and _ as in Meta"),
    wa_language: z.string().trim().max(10),
    status: z.enum(["draft", "active"]),
  })
  .superRefine((v, ctx) => {
    const bad = unknownVariables(`${v.body} ${v.subject}`);
    if (bad.length) ctx.addIssue({ code: "custom", path: ["body"], message: `Unknown variable: ${bad.join(", ")}` });
    if (v.channel === "email" && v.subject.length < 3) ctx.addIssue({ code: "custom", path: ["subject"], message: "Add a subject" });
    if (v.channel === "whatsapp" && v.status === "active" && !v.wa_template) {
      ctx.addIssue({ code: "custom", path: ["wa_template"], message: "Give the approved template name before activating" });
    }
  });

export type TemplateInput = z.infer<typeof TemplateSchema>;

export function zodErrors(issues: { path: PropertyKey[]; message: string }[]): Record<string, string> {
  const errors: Record<string, string> = {};
  for (const i of issues) errors[String(i.path[0])] ??= i.message;
  return errors;
}
