import "server-only";
// Shared plumbing for the ledger, payout and earnings server actions: validate → signed-in client → one RPC, with
// database errors mapped to finance.errors.* message keys.
import { revalidatePath } from "next/cache";
import { getTranslations } from "next-intl/server";
import type { z } from "zod";
import { fail, type ActionResult } from "@/lib/actions/result";
import { fetchMe } from "@/lib/auth/guards";
import { log } from "@/lib/log";
import { createClient, type ServerSupabase } from "@/lib/supabase/server";
import { LEDGER_DB_ERRORS } from "./schemas";

export type T = Awaited<ReturnType<typeof getTranslations>>;

async function signedIn(): Promise<ServerSupabase | null> {
  const supabase = await createClient();
  const me = await fetchMe(supabase);
  if (!me.signed_in || !me.session?.verified || me.session.revoked) return null;
  return supabase;
}

export function ledgerDbFail(error: { code?: string; message: string }, t: T): ActionResult<never> {
  if (error.code === "42501") return fail(t("errors.forbidden"));
  for (const [re, key] of LEDGER_DB_ERRORS)
    if (re.test(error.message)) return fail(t(`finance.errors.${key}` as "finance.errors.stale"));
  if (["22023", "23514", "23505", "40001"].includes(error.code ?? "")) return fail(t("errors.invalidInput"));
  log.warn("ledger.db_error", { code: error.code, error: error.message });
  return fail(t("errors.generic"));
}

export async function act<S extends z.ZodType, Res extends ActionResult<unknown>>(
  schema: S,
  input: unknown,
  body: (db: ServerSupabase, v: z.output<S>, t: T) => Promise<Res>,
): Promise<Res | ActionResult<never>> {
  const t = await getTranslations();
  const parsed = schema.safeParse(input);
  if (!parsed.success) return fail(t("errors.invalidInput"));
  const supabase = await signedIn();
  if (!supabase) return fail(t("errors.sessionEnded"));
  return body(supabase, parsed.data, t);
}

export function refreshFinance() {
  revalidatePath("/admin/finance", "layout");
  revalidatePath("/admin/deals", "layout");
  revalidatePath("/creator/earnings");
  revalidatePath("/creator/leads");
  revalidatePath("/agency", "layout");
}
