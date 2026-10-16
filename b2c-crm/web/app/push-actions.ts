"use server";
import { z } from "zod";
import { assertUser } from "@/lib/auth";
import { act, rpc, type ActionResult } from "@/lib/data";

const sub = z.object({ endpoint: z.string().url().max(1000), keys: z.object({ p256dh: z.string().max(200), auth: z.string().max(100) }).optional() });

/** This device's push subscription on or off (b2c.push_subscribe accepts only the browsers' push services). */
export async function pushSubscribe(input: unknown, on: boolean): Promise<ActionResult<number>> {
  await assertUser();
  const p = sub.safeParse(input);
  if (!p.success) return { ok: false, error: "This browser gave an unusable subscription." };
  return act(() => rpc<number>("push_subscribe", { p_sub: p.data, p_on: on }), on ? "Alerts are on for this device." : "Alerts are off for this device.");
}
