// Pure mappings between the b2c outbox and the B2B CRM API. Unit-tested in b2b-map.test.ts.

export type IntakeBody = {
  lead: Record<string, string>;
  source: string;
  channel?: string;
  consent?: { sales_at?: string | null; partner_share_at?: string | null; marketing_at?: string | null; text_version?: string | null };
  occurred_at?: string;
  route: "b2c";
  b2c_lane: "sales" | "nurture";
};

/** Turns an outbox intake item (b2c.new_lead or b2c.wa_inbound) into the Intake API body. Unit-tested in b2b.test.ts. */
export function intakeBody(item: Record<string, unknown>, occurredAt: string): IntakeBody {
  const s = (k: string) => (typeof item[k] === "string" && item[k] ? (item[k] as string) : undefined);
  const others = Array.isArray(item.other_courses) ? (item.other_courses as unknown[]).filter((x) => typeof x === "string") as string[] : [];
  const notes = [s("notes"), others.length ? `Also interested in: ${others.join(", ")}` : undefined, s("first_message") ? `First message: ${s("first_message")}` : undefined]
    .filter(Boolean).join("\n");
  const lead: Record<string, string> = { phone: s("phone") ?? "" };
  if (s("name")) lead.full_name = s("name")!;
  if (s("email")) lead.email = s("email")!;
  if (s("course")) lead.course = s("course")!;
  if (s("city")) lead.city = s("city")!;
  if (notes) lead.notes = notes.slice(0, 500);
  const source = s("lead_source") ?? "b2c_created";
  const body: IntakeBody = { lead, source, channel: source === "b2c_whatsapp" ? "whatsapp" : "b2c_crm", occurred_at: occurredAt, route: "b2c", b2c_lane: "sales" };
  if (s("consent_text_version")) body.consent = { sales_at: occurredAt, partner_share_at: occurredAt, text_version: s("consent_text_version") };
  return body;
}
