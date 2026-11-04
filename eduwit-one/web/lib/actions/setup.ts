"use server";
import { z } from "zod";
import { resetVaultCache } from "../clients/credentials.ts";
import { assertUser } from "../session.ts";
import { runValidate } from "../setup/run.ts";
import { act, fields, invalid, type ActionResult } from "./act.ts";

/** Saves a secret to Vault under its one_* name (owner only; the value never comes back). */
export async function saveSecret(_: ActionResult | undefined, form: FormData): Promise<ActionResult> {
  const p = z
    .object({
      name: z.string().regex(/^one_[a-z0-9_]+$/),
      value: z.string().min(8, "That value looks too short.").max(8192),
    })
    .safeParse(fields(form));
  if (!p.success) return invalid(p.error.issues);
  const r = await act(
    "ui_secret_put",
    { p_name: p.data.name, p_value: p.data.value.trim() },
    "Saved to Vault. Press validate to check it.",
  );
  resetVaultCache();
  return r;
}

/** Runs an item's validator on the server with the real client, and records the verdict (spec §15; lib/setup/run.ts). */
export async function validateItem(_: ActionResult | undefined, form: FormData): Promise<ActionResult> {
  const p = z.object({ id: z.string().regex(/^[a-z0-9_]+$/) }).safeParse(fields(form));
  if (!p.success) return invalid(p.error.issues);
  let me;
  try {
    me = await assertUser();
  } catch {
    return { ok: false, error: "Your role cannot do this." };
  }
  const verdict = await runValidate(p.data.id, me.email);
  return verdict.ok
    ? { ok: true, message: `Validated: ${verdict.detail}` }
    : { ok: false, error: `Not validated: ${verdict.detail}` };
}
