"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertUser } from "@/lib/auth";
import { act, rpc, type ActionResult } from "@/lib/data";

/** Personal connectors (spec B17): each person turns their own Calendar sync on or off. */
export async function calendarSet(on: boolean): Promise<ActionResult<{ on: boolean; queued: number }>> {
  await assertUser();
  const r = await act(() => rpc<{ on: boolean; queued: number }>("calendar_set", { p_on: on }),
    on ? "Your follow-ups will appear in your Google Calendar within a few minutes." : "Your follow-ups will be removed from your Google Calendar.");
  revalidatePath("/w/connectors");
  revalidatePath("/s/me");
  return r;
}

/** The Admin marks a missed call from an unknown number as dealt with. */
export async function unknownCallHandled(id: number, note: string): Promise<ActionResult> {
  await assertUser(["admin"]);
  const r = await act(() => rpc("unknown_call_handled", { p_id: z.coerce.number().int().positive().parse(id), p_note: note.slice(0, 300) || null }), "Marked as handled.");
  revalidatePath("/w/connectors");
  revalidatePath("/w");
  return r;
}
