"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertUser } from "@/lib/auth";
import { act, rpc, type ActionResult } from "@/lib/data";

const SALES = ["counsellor", "sales_head", "admin"] as const;
const ids = z.array(z.coerce.number().int().positive()).min(1).max(200);
const iso = z.string().datetime({ offset: true });

/** A tag on the ticked leads: a counsellor on their own leads, the Admin and Marketing on any (b2c.tag_own). */
export async function tagOwn(leads: number[], tag: string, add: boolean): Promise<ActionResult<number>> {
  await assertUser([...SALES, "marketing"]);
  const r = await act(() => rpc<number>("tag_own", { p_leads: ids.parse(leads), p_tag: tag.trim().slice(0, 40), p_add: add }), add ? "Tagged." : "Tag removed.");
  revalidatePath("/s/leads");
  return r;
}

const taskSchema = z.object({ kind: z.enum(["call", "whatsapp", "email", "document", "followup", "qualify"]).default("call"), title: z.string().trim().min(2).max(120), due: iso, note: z.string().max(300).optional() });

/** The same follow-up on every ticked lead (own leads; the rest are named back). */
export async function tasksBulk(leads: number[], input: z.input<typeof taskSchema>): Promise<ActionResult<{ created: number; skipped: { lead_id: number; why: string }[] }>> {
  await assertUser([...SALES]);
  const p = taskSchema.safeParse(input);
  if (!p.success) return { ok: false, error: "Say what the follow-up is and when." };
  const r = await act(() => rpc<{ created: number; skipped: { lead_id: number; why: string }[] }>("tasks_bulk", {
    p_leads: ids.parse(leads).slice(0, 100), p_kind: p.data.kind, p_title: p.data.title, p_due: p.data.due, p_note: p.data.note ?? null,
  }));
  revalidatePath("/s", "layout");
  return r;
}

/** One approved sales template to the ticked leads, under the single-send rules; each refusal is named. */
export async function waBulk(leads: number[], templateId: number): Promise<ActionResult<{ sent: number; refused: { lead_id: number; why: string }[] }>> {
  await assertUser([...SALES]);
  const r = await act(() => rpc<{ sent: number; refused: { lead_id: number; why: string }[] }>("wa_bulk_template", {
    p_leads: ids.parse(leads).slice(0, 50), p_template: z.coerce.number().int().positive().parse(templateId),
  }));
  revalidatePath("/s", "layout");
  return r;
}

/** "Suggest a correction" on the Programme page: a support ticket to the Admin, who is told at once. */
export async function catalogueSuggest(programmeId: number, note: string): Promise<ActionResult<{ number: string }>> {
  await assertUser();
  return act(() => rpc<{ number: string }>("catalogue_suggest", { p_programme: z.coerce.number().int().positive().parse(programmeId), p_note: note.trim().slice(0, 4000) }),
    "Thank you. The Admin has it as a support ticket.");
}
