"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertUser } from "@/lib/auth";
import { act, rpc, type ActionResult } from "@/lib/data";

export type Snippet = { id: number; title: string; body: string; shared: boolean; uses: number; mine: boolean; author: string | null; updated_at: string };

const schema = z.object({ id: z.coerce.number().int().positive().optional(), title: z.string().trim().min(1).max(60), body: z.string().trim().min(1).max(1000), shared: z.boolean().optional() });

/** Saved WhatsApp snippets (spec B8.5): the person's own, and the ones colleagues share. */
export async function snippetsMine(): Promise<Snippet[]> {
  await assertUser();
  return rpc<Snippet[]>("snippets_mine");
}

export async function snippetSave(input: z.input<typeof schema>): Promise<ActionResult<number>> {
  await assertUser();
  const p = schema.safeParse(input);
  if (!p.success) return { ok: false, error: "Give the snippet a name and some text (at most 1,000 characters)." };
  const r = await act(() => rpc<number>("snippet_save", { p: p.data }), p.data.id ? "Snippet saved." : "Snippet added.");
  revalidatePath("/s/me");
  revalidatePath("/s/inbox");
  return r;
}

export async function snippetDelete(id: number): Promise<ActionResult> {
  await assertUser();
  const r = await act(() => rpc("snippet_delete", { p_id: z.coerce.number().int().positive().parse(id) }), "Snippet removed.");
  revalidatePath("/s/me");
  revalidatePath("/s/inbox");
  return r;
}

/** Counted when a snippet is inserted into a message, so the useful ones rise to the top. */
export async function snippetUsed(id: number): Promise<void> {
  await assertUser();
  await rpc("snippet_used", { p_id: z.coerce.number().int().positive().parse(id) }).catch(() => undefined);
}
