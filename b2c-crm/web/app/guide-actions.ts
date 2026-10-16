"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertUser } from "@/lib/auth";
import { act, rpc, type ActionResult } from "@/lib/data";

export type Article = {
  id: number; role: "sales" | "marketing" | "admin"; slug: string; section: string; title: string; body: string; screens: string[]; sort: number;
  version: number; updated_at: string; archived: boolean; read: boolean; read_at: string | null;
};
export type Reader = { user_id: string; name: string; role: string; total: number; read: number };

/** The person's guide (the Admin: all three, or one). */
export async function guidesList(role?: "sales" | "marketing" | "admin", archived = false): Promise<ActionResult<Article[]>> {
  await assertUser();
  return act(() => rpc<Article[]>("guides", { p_role: role ?? null, p_archived: archived }));
}

export async function guideRead(id: number): Promise<void> {
  await assertUser();
  await rpc("guide_read", { p_id: z.coerce.number().int().positive().parse(id) }).catch(() => undefined);
}

const saveSchema = z.object({
  id: z.coerce.number().int().positive().optional(), role: z.enum(["sales", "marketing", "admin"]).optional(),
  section: z.string().trim().max(60).optional(), title: z.string().trim().min(1).max(120), body: z.string().trim().min(1).max(20000),
  screens: z.array(z.string().trim().regex(/^\/[a-z0-9/_*-]*$/)).max(20).optional(), sort: z.coerce.number().int().min(0).max(10000).optional(),
  archived: z.boolean().optional(),
});

export async function guideSave(input: z.input<typeof saveSchema>): Promise<ActionResult<number>> {
  await assertUser(["admin"]);
  const p = saveSchema.safeParse(input);
  if (!p.success) return { ok: false, error: "Give the article a title and text; screens look like /s/leads or /s/leads/*." };
  const r = await act(() => rpc<number>("guide_save", { p: p.data }), "Article saved.");
  revalidatePath("/w/guide");
  revalidatePath("/s/me");
  return r;
}

export async function guideReaders(): Promise<ActionResult<Reader[]>> {
  await assertUser(["admin"]);
  return act(() => rpc<Reader[]>("guide_readers"));
}
