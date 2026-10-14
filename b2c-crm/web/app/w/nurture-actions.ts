"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertUser } from "@/lib/auth";
import { act, rpc, type ActionResult } from "@/lib/data";
import { createClient } from "@/lib/supabase/server";
import { submitTemplate, type TemplateRow } from "@/lib/wa-templates";

/** Marketing workspace actions (spec B9). Admin and Marketing; every function checks the role again in the database. */
const MKT = ["admin", "marketing"] as const;
const id = z.coerce.number().int().positive();
const done = (...paths: string[]) => { for (const p of ["/w/nurture", ...paths]) revalidatePath(p); };

// ---------- segments ----------
export async function segmentCount(filters: unknown, segment?: number): Promise<ActionResult<Record<string, number>>> {
  await assertUser([...MKT]);
  return act(() => rpc("segment_count", { p_segment: segment ?? null, p_filters: segment ? null : filters }));
}
export async function segmentSave(p: Record<string, unknown>): Promise<ActionResult<number>> {
  await assertUser([...MKT]);
  const r = await act(() => rpc<number>("segment_save", { p }), "Segment saved.");
  done();
  return r;
}
export async function segmentAddPhones(segment: number, phones: string[]): Promise<ActionResult<{ added: number; total: number; not_found: number }>> {
  await assertUser([...MKT]);
  const r = await act(() => rpc<{ added: number; total: number; not_found: number }>("segment_add", { p_segment: id.parse(segment), p_leads: null, p_phones: phones.slice(0, 20000), p_filters: null }));
  done();
  return r;
}
export async function segmentSnapshot(segment: number, filters: unknown): Promise<ActionResult<{ added: number; total: number }>> {
  await assertUser([...MKT]);
  const r = await act(() => rpc<{ added: number; total: number }>("segment_add", { p_segment: id.parse(segment), p_leads: null, p_phones: null, p_filters: filters }));
  done();
  return r;
}
export async function segmentOverlap(a: number, b: number): Promise<ActionResult<{ a: number; b: number; both: number }>> {
  await assertUser([...MKT]);
  return act(() => rpc("segment_overlap", { p_a: id.parse(a), p_b: id.parse(b) }));
}

// ---------- campaigns ----------
export async function campaignSave(p: Record<string, unknown>): Promise<ActionResult<number>> {
  await assertUser([...MKT]);
  const r = await act(() => rpc<number>("campaign_save", { p }), "Campaign saved.");
  done();
  return r;
}
export async function campaignSet(campaign: number, action: "schedule" | "pause" | "cancel"): Promise<ActionResult<string>> {
  await assertUser([...MKT]);
  const r = await act(() => rpc<string>("campaign_set", { p_id: id.parse(campaign), p_action: action }), action === "schedule" ? "Scheduled." : action === "pause" ? "Paused." : "Cancelled.");
  done();
  return r;
}
export async function campaignClone(campaign: number): Promise<ActionResult<number>> {
  await assertUser([...MKT]);
  const r = await act(() => rpc<number>("campaign_clone", { p_id: id.parse(campaign) }), "Copied as a draft.");
  done();
  return r;
}
export async function campaignStats(campaign: number): Promise<ActionResult<Record<string, unknown>>> {
  await assertUser([...MKT]);
  return act(() => rpc("campaign_stats", { p_id: id.parse(campaign) }));
}

// ---------- journeys ----------
export async function journeySave(p: Record<string, unknown>): Promise<ActionResult<number>> {
  await assertUser([...MKT]);
  const r = await act(() => rpc<number>("journey_save", { p }), "Draft saved.");
  done(p.id ? `/w/nurture/journeys/${p.id}` : "/w/nurture");
  return r;
}
export async function journeyPublish(journey: number, migrate: boolean): Promise<ActionResult<number>> {
  await assertUser([...MKT]);
  const r = await act(() => rpc<number>("journey_publish", { p_id: id.parse(journey), p_migrate: migrate }), "Published.");
  done(`/w/nurture/journeys/${journey}`);
  return r;
}
export async function journeySet(journey: number, status: "active" | "paused" | "archived"): Promise<ActionResult> {
  await assertUser([...MKT]);
  const r = await act(() => rpc("journey_set", { p_id: id.parse(journey), p_status: status }), status === "active" ? "Journey running." : status === "paused" ? "Journey paused." : "Journey archived.");
  done(`/w/nurture/journeys/${journey}`);
  return r;
}
export async function journeyClone(journey: number): Promise<ActionResult<number>> {
  await assertUser([...MKT]);
  const r = await act(() => rpc<number>("journey_clone", { p_id: id.parse(journey) }), "Copied as a draft in test mode.");
  done();
  return r;
}
export async function journeyTest(journey: number, lead: number): Promise<ActionResult<number>> {
  await assertUser([...MKT]);
  const r = await act(() => rpc<number>("journey_test", { p_id: id.parse(journey), p_lead: id.parse(lead) }), "Test run started on the test lead.");
  done(`/w/nurture/journeys/${journey}`);
  return r;
}

// ---------- the lead level ----------
export async function journeyLead(lead: number, action: "start" | "stop" | "pause" | "resume", journey?: number): Promise<ActionResult> {
  await assertUser([...MKT]);
  const r = await act(() => rpc("journey_lead", { p_lead: id.parse(lead), p_action: action, p_journey: journey ?? null }), "Done.");
  done(`/w/leads/${lead}`);
  return r;
}
export async function nurtureSend(lead: number, channel: "whatsapp" | "email", template: number): Promise<ActionResult<{ message_id?: number; email_id?: number; blocked?: string }>> {
  await assertUser([...MKT]);
  const r = await act(() => rpc<{ message_id?: number; email_id?: number; blocked?: string }>("nurture_send", { p_lead: id.parse(lead), p_channel: channel, p_template: id.parse(template) }));
  if (r.ok && r.data?.blocked) return { ok: false, error: `Not sent: ${r.data.blocked}.` };
  done(`/w/leads/${lead}`);
  return r.ok ? { ...r, notice: "Queued." } : r;
}
export async function nurtureHandover(lead: number, reason: string): Promise<ActionResult> {
  await assertUser([...MKT]);
  const r = await act(() => rpc("nurture_handover", { p_lead: id.parse(lead), p_reason: reason }), "Handed to a counsellor.");
  done(`/w/leads/${lead}`);
  return r;
}
export async function optOut(lead: number, channels: ("whatsapp" | "email")[] | null, note?: string): Promise<ActionResult> {
  await assertUser();
  const r = await act(() => rpc("opt_out", { p_lead: id.parse(lead), p_channels: channels, p_source: "staff", p_note: note ?? null }), "Opt-out recorded and sent to the master lead table.");
  done(`/w/leads/${lead}`, `/s/leads/${lead}`);
  return r;
}
export async function marketingConsent(lead: number, channel: "whatsapp" | "email", given: boolean, source: string): Promise<ActionResult> {
  await assertUser([...MKT]);
  const r = await act(() => rpc("marketing_consent", { p_lead: id.parse(lead), p_channel: channel, p_given: given, p_source: source, p_text_version: null, p_text: null }), "Consent recorded.");
  done(`/w/leads/${lead}`);
  return r;
}

// ---------- replies ----------
export async function replyHandle(reply: number, action: "assign" | "negative" | "opt_out" | "correct" | "done", klass?: string): Promise<ActionResult<string>> {
  await assertUser([...MKT]);
  const r = await act(() => rpc<string>("reply_handle", { p_id: id.parse(reply), p_action: action, p_class: klass ?? null }), "Done.");
  done();
  return r;
}
export async function replyAnswer(lead: number, text: string): Promise<ActionResult> {
  await assertUser([...MKT]);
  const r = await act(() => rpc("wa_queue_reply", { p_lead: id.parse(lead), p_text: text.slice(0, 4096) }), "Answer queued.");
  done();
  return r;
}

// ---------- scoring and suppression ----------
export async function scoreRuleSave(key: string, points: number, active: boolean): Promise<ActionResult> {
  await assertUser([...MKT]);
  const r = await act(() => rpc("score_rule_save", { p_key: key, p_points: Math.round(points), p_active: active }), "Rule saved.");
  done();
  return r;
}
export async function suppress(value: string, reason: string, on: boolean): Promise<ActionResult> {
  await assertUser([...MKT]);
  const r = await act(() => rpc("suppress", { p_value: value, p_reason: reason, p_on: on }), on ? "Added to the suppression list." : "Removed from the suppression list.");
  done();
  return r;
}

// ---------- templates ----------
export async function waTemplateSave(p: Record<string, unknown>): Promise<ActionResult<number>> {
  await assertUser([...MKT]);
  const r = await act(() => rpc<number>("wa_template_save", { p }), "Template saved. Submit it to Meta when ready.");
  revalidatePath("/w/templates");
  return r;
}
export async function emailTemplateMSave(p: Record<string, unknown>): Promise<ActionResult<number>> {
  await assertUser([...MKT]);
  const r = await act(() => rpc<number>("email_template_m_save", { p }), "Template saved.");
  revalidatePath("/w/templates");
  return r;
}
export async function waTemplateSubmit(template: number): Promise<ActionResult> {
  await assertUser([...MKT]);
  const supabase = await createClient();
  const { data: t, error } = await supabase.from("wa_templates").select("id, name, language, category, body, variables, buttons, audience").eq("id", id.parse(template)).maybeSingle();
  if (error || !t) return { ok: false, error: "Template not found." };
  const mark = await act(() => rpc("wa_template_submitted", { p_id: t.id }));
  if (!mark.ok) return mark;
  const r = await submitTemplate(t as unknown as TemplateRow);
  revalidatePath("/w/templates");
  return r.ok ? { ok: true, notice: "Submitted to Meta. Approval usually takes minutes to a day." } : { ok: false, error: r.error ?? "Meta refused it." };
}

// ---------- the lead screen's nurture panel ----------
export type LeadNurture = {
  score: { score: number | null; fit: number; engagement: number; band: string | null; dormant_at: string | null } | null;
  consent: { whatsapp: boolean; email: boolean; history: { channel: string; given: boolean; source: string; at: string }[] };
  runs: { id: number; journey: string; key: string; status: string; step: number; next_at: string; entered_at: string; exited_at: string | null; exit_reason: string | null;
          log: { at: string; step: number; type: string | null; outcome: string; detail: Record<string, unknown> }[] }[];
  replies: { id: number; channel: string; text: string | null; button: string | null; class: string | null; corrected_class: string | null; status: string; created_at: string }[];
};
export type NurtureOptions = { journeys: { id: number; name: string; status: string }[]; templates: { id: number; name: string; channel: "whatsapp" | "email" }[] };

export async function leadNurture(lead: number): Promise<ActionResult<{ data: LeadNurture; options: NurtureOptions | null }>> {
  const me = await assertUser();
  const r = await act(() => rpc<LeadNurture>("lead_nurture", { p_lead: id.parse(lead) }));
  if (!r.ok) return r;
  let options: NurtureOptions | null = null;
  if (me.role === "admin" || me.role === "marketing") {
    const supabase = await createClient();
    const [{ data: j }, { data: wa }, { data: em }] = await Promise.all([
      supabase.from("journeys").select("id, name, status").gt("current_version", 0).neq("status", "archived").order("name"),
      supabase.from("wa_templates").select("id, name").eq("audience", "marketing").is("archived_at", null).order("name"),
      supabase.from("email_templates").select("id, name").is("archived_at", null).order("name"),
    ]);
    options = { journeys: (j ?? []) as NurtureOptions["journeys"], templates: [...(wa ?? []).map((t) => ({ ...t, channel: "whatsapp" as const })), ...(em ?? []).map((t) => ({ ...t, channel: "email" as const }))] };
  }
  return { ok: true, data: { data: r.data!, options } };
}
