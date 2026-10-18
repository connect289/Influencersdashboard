"use server";
// Saved views for the lead pipeline (each person's own; staff may share theirs with other staff).
import { LEAD_FILTER_KEYS } from "@/lib/leads/filters";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { fetchMe } from "@/lib/auth/guards";
import { createClient } from "@/lib/supabase/server";
import { fail, type ActionResult } from "./result";

const viewInput = z.object({
  name: z.string().trim().min(1).max(60),
  filters: z.partialRecord(z.enum(LEAD_FILTER_KEYS), z.string().max(80)),
  shared: z.boolean(),
});

async function client() {
  const supabase = await createClient();
  const me = await fetchMe(supabase);
  return me.signed_in && me.session?.verified && !me.session.revoked ? supabase : null;
}

export async function saveLeadView(input: z.input<typeof viewInput>): Promise<ActionResult> {
  const t = await getTranslations();
  const v = viewInput.safeParse(input);
  if (!v.success) return fail(t("errors.invalidInput"));
  const supabase = await client();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("lead_view_save", {
    p_name: v.data.name,
    p_filters: v.data.filters,
    p_shared: v.data.shared,
  });
  if (error) return fail(error.code === "42501" ? t("errors.forbidden") : t("errors.generic"));
  return { ok: true, message: t("leads.views.saved") };
}

export async function deleteLeadView(id: string): Promise<ActionResult> {
  const t = await getTranslations();
  if (!z.uuid().safeParse(id).success) return fail(t("errors.invalidInput"));
  const supabase = await client();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("lead_view_delete", { p_id: id });
  if (error) return fail(t("errors.generic"));
  return { ok: true };
}
