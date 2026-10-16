"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertUser } from "@/lib/auth";
import { act, friendly, rpc, type ActionResult } from "@/lib/data";
import { liveMode, siteUrl } from "@/lib/env";
import { adminClient } from "@/lib/supabase/admin";
import { exotelConfig, exotelConnect } from "@/lib/telephony";

/**
 * The Call button (spec B8.4). b2c.call_start decides: provider none → the manual tel: flow with the log sheet (today);
 * otherwise a bridged call through the provider (Exotel), or the mock for test leads. A real provider is called only
 * with LIVE_MODE=on and its credentials set; when it refuses, the call is marked "not placed" and nothing is counted.
 */
const SALES = ["counsellor", "sales_head", "admin"] as const;
const id = z.coerce.number().int().positive();

export type CallStart =
  | { mode: "manual"; call_id: number; number: string; tel: string }
  | { mode: "bridge"; provider: string; call_id: number; number: string; tel: string; agent: string };

export async function callStart(leadId: number, contactId?: number): Promise<ActionResult<CallStart>> {
  await assertUser([...SALES]);
  let r: CallStart & { student?: string; caller_id?: string | null };
  try {
    r = await rpc("call_start", { p_lead: id.parse(leadId), p_contact: contactId ?? null });
  } catch (e) {
    return { ok: false, error: friendly(e) };
  }
  if (r.mode === "manual" || r.provider === "mock") return { ok: true, data: r };
  const fail = async (why: string) => {
    await adminClient().rpc("call_start_failed", { p_call: r.call_id, p_error: why });
    revalidatePath(`/s/leads/${leadId}`);
    return { ok: false as const, error: `The call was not placed: ${why}` };
  };
  if (r.provider !== "exotel") return fail(`unknown provider ${r.provider}`);
  const cfg = exotelConfig();
  if (!cfg) return fail("Exotel is not set up (EXOTEL_SID, EXOTEL_API_KEY, EXOTEL_API_TOKEN, EXOTEL_WEBHOOK_KEY).");
  if (!liveMode()) return fail("LIVE_MODE is off, so no real call is placed.");
  try {
    const started = await exotelConnect(cfg, { agent: r.agent, student: r.student ?? r.number, callerId: r.caller_id ?? null, callId: r.call_id,
      callbackUrl: `${siteUrl()}/v1/webhooks/telephony/exotel?key=${encodeURIComponent(cfg.webhookKey)}` });
    if (started.sid) await adminClient().rpc("call_event", { p: { provider: "exotel", call_id: r.call_id, provider_ref: started.sid, status: "initiated" } });
    return { ok: true, data: r };
  } catch (e) {
    return fail(e instanceof Error ? e.message : String(e));
  }
}

export type CallView = { id: number; provider: string; status: string | null; outcome: string | null; duration_s: number | null; logged: boolean; ended: boolean; note: string | null; recording: string };

export async function callGet(callId: number): Promise<ActionResult<CallView>> {
  await assertUser([...SALES]);
  return act(() => rpc<CallView>("call_get", { p_call: id.parse(callId) }));
}

/** The mock provider, played from the call sheet (test leads only, never a real call). */
export async function callMock(callId: number, status: "answered" | "completed" | "no_answer" | "busy" | "agent_no_answer", minutes = 0, leadId?: number): Promise<ActionResult> {
  await assertUser([...SALES]);
  const r = await act(() => rpc("call_mock_event", { p_call: id.parse(callId), p_status: status, p_duration_s: Math.round(minutes * 60) }));
  if (leadId) revalidatePath(`/s/leads/${leadId}`);
  return r;
}

export async function callNote(callId: number, note: string, leadId?: number): Promise<ActionResult> {
  await assertUser([...SALES]);
  const r = await act(() => rpc("call_note", { p_call: id.parse(callId), p_note: z.string().trim().min(1).max(2000).parse(note) }), "Note added.");
  if (leadId) revalidatePath(`/s/leads/${leadId}`);
  return r;
}

/** A recording, for someone who may see the lead (the play is logged): a signed link valid for 5 minutes. */
export async function recordingLink(callId: number): Promise<ActionResult<string>> {
  await assertUser();
  try {
    const path = await rpc<string>("recording_open", { p_call: id.parse(callId) });
    const { data, error } = await adminClient().storage.from("b2c-recordings").createSignedUrl(path, 300);
    if (error || !data) return { ok: false, error: "The recording could not be opened." };
    return { ok: true, data: data.signedUrl };
  } catch (e) {
    return { ok: false, error: friendly(e) };
  }
}
