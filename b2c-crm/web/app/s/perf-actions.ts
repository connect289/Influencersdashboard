"use server";
import { revalidatePath } from "next/cache";
import { assertUser } from "@/lib/auth";
import { act, rpc, type ActionResult } from "@/lib/data";

/** The counsellor's own performance settings (spec B11.3). */
export async function leaderboardOpt(visible: boolean): Promise<ActionResult> {
  await assertUser();
  const r = await act(() => rpc("leaderboard_opt", { p_visible: visible }), visible ? "Your name shows on the leaderboard." : "You show as “A counsellor”.");
  revalidatePath("/s");
  return r;
}
