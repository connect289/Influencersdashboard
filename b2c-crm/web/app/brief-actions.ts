"use server";
import { z } from "zod";
import { AiUnavailable } from "@/lib/ai";
import { writeBrief } from "@/lib/analytics-ai";
import { assertUser } from "@/lib/auth";
import { act, friendly, rpc, type ActionResult } from "@/lib/data";

/** Brief before you call (spec B8.3). Reading checks the person may see the lead; writing runs only after that check. */
export type Brief = { lines: { text: string; source: string }[]; written_at: string | null; model: string | null; error: string | null; stale: boolean };
const id = z.coerce.number().int().positive();

export async function briefGet(lead: number): Promise<ActionResult<Brief>> {
  await assertUser();
  return act(() => rpc<Brief>("brief_get", { p_lead: id.parse(lead) }));
}

export async function briefRefresh(lead: number): Promise<ActionResult<Brief>> {
  const me = await assertUser();
  const l = id.parse(lead);
  try {
    const now = await rpc<Brief>("brief_get", { p_lead: l });   // raises unless this person may see the lead
    if (!now.stale && now.written_at && Date.now() - new Date(now.written_at).getTime() < 60_000) return { ok: true, data: now };
    await writeBrief(l, me.user_id!);
    return { ok: true, data: await rpc<Brief>("brief_get", { p_lead: l }), notice: "Brief written." };
  } catch (e) {
    return { ok: false, error: e instanceof AiUnavailable ? e.message : friendly(e) };
  }
}
