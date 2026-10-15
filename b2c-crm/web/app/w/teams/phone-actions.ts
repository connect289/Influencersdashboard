"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertUser } from "@/lib/auth";
import { act, rpc, type ActionResult } from "@/lib/data";

/** The Admin allocates, changes or moves a person's work mobile or caller ID (b2c.phone_set keeps the history). */
export async function phoneSet(p: { user_id: string; kind: "mobile" | "caller_id"; number: string; reason: string; move?: boolean }): Promise<ActionResult<{ number: string | null; moved_from: string | null }>> {
  await assertUser(["admin"]);
  const v = z.object({ user_id: z.string().uuid(), kind: z.enum(["mobile", "caller_id"]), number: z.string().max(30), reason: z.string().trim().min(3, "Give a reason.").max(200), move: z.boolean().optional() }).safeParse(p);
  if (!v.success) return { ok: false, error: v.error.issues[0]?.message ?? "Check the number." };
  const r = await act(() => rpc<{ number: string | null; moved_from: string | null }>("phone_set", { p: v.data }), "Saved. The person is told.");
  revalidatePath("/w/teams");
  return r;
}
