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

/** An item b2c.outbox_take hands out. */
export type OutboxItem = {
  id: number;
  kind: "update" | "activity" | "event" | "route" | "intake";
  lead_id: number | null;
  request_id: string;
  body: Record<string, unknown>;
  occurred_at: string;
  actor: { id?: string; email?: string; name?: string } | null;
  urgent: boolean;
};

/** What b2c.outbox_done needs for each item: ok, the HTTP status, and B2B's answer (it reads answer.record / answer.result). */
export type DoneResult = { id: number; ok: boolean; status: number; answer: Record<string, unknown> };

/** §3.8 batch item for an update or an activity, with occurred_at (Addendum 4 §2). */
export function toBatchItem(o: OutboxItem): Record<string, unknown> {
  const base = { lead_id: o.lead_id, request_id: o.request_id, actor: o.actor ?? undefined };
  if (o.kind === "update") return { op: "update", ...base, set: (o.body.set as Record<string, unknown>) ?? {}, occurred_at: o.occurred_at };
  return { op: "activity", ...base, ...o.body };
}

/** Matches the batch answer's items to the outbox rows. A failed call fails every item with the call's status. */
export function batchDone(items: OutboxItem[], status: number, body: Record<string, unknown>): DoneResult[] {
  const answers = (((body.result as Record<string, unknown> | undefined)?.items ?? body.items) as Record<string, unknown>[] | undefined) ?? [];
  return items.map((o) => {
    if (status < 200 || status >= 300) return { id: o.id, ok: false, status, answer: body };
    const a = answers.find((x) => x.request_id === o.request_id);
    if (!a) return { id: o.id, ok: false, status: 502, answer: { error: "missing from the batch answer" } };
    return { id: o.id, ok: a.ok === true, status: Number(a.status ?? (a.ok ? 200 : 500)), answer: a };
  });
}

/** One answer from a single call: 2xx with ok !== false is success. The answer kept is the result when there is one. */
export function singleDone(o: OutboxItem, status: number, body: Record<string, unknown>): DoneResult {
  const ok = status >= 200 && status < 300 && body.ok !== false;
  const answer = (ok && body.result && typeof body.result === "object" ? { ...(body.result as Record<string, unknown>), result: body.result } : body) as Record<string, unknown>;
  return { id: o.id, ok, status, answer };
}

/** Splits into chunks of at most `size` items (the batch endpoint takes 200 a call). */
export function chunks<T>(xs: T[], size = 200): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < xs.length; i += size) out.push(xs.slice(i, i + size));
  return out;
}

/** A change-feed entry as an envelope, so the feed and the webhooks share one de-duplication path (b2c.handoff_receive). */
export function feedEnvelope(e: { type: string; lead_id: number; version: number; seq: number; changed_at?: string; origin?: string | null; record: unknown }): Record<string, unknown> {
  return { id: `feed-${e.seq}`, type: e.type, lead_id: e.lead_id, occurred_at: e.changed_at ?? new Date().toISOString(),
           data: { version: e.version, seq: e.seq, origin: e.origin ?? "feed", record: e.record } };
}
