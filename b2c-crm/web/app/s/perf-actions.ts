"use server";
import { revalidatePath } from "next/cache";
import { allowed } from "@/lib/auth";
import { act, rpc, type ActionResult } from "@/lib/data";

/** The counsellor's own performance settings (spec B11.3). */
export async function leaderboardOpt(visible: boolean): Promise<ActionResult> {
  const gate = await allowed();
  if (!gate.ok) return gate;
  const r = await act(() => rpc("leaderboard_opt", { p_visible: visible }), visible ? "Your name shows on the leaderboard." : "You show as “A counsellor”.");
  revalidatePath("/s");
  return r;
}
