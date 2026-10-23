"use server";
import { z } from "zod";
import { credentialsFrom, resetVaultCache, vaultSecrets } from "../clients/credentials.ts";
import { SupabaseOneDb } from "../db.ts";
import { log } from "../log.ts";
import { assertUser } from "../session.ts";
import { validate } from "../setup/validate.ts";
import { ui } from "../ui/api.ts";
import { checksSchema, heartbeatsSchema, setupSchema } from "../ui/schemas.ts";
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
    ["/settings/setup"],
    "Saved to Vault. Press validate to check it.",
  );
  resetVaultCache();
  return r;
}

/** Runs an item's validator on the server with the real client, and records the verdict (spec §15). */
export async function validateItem(_: ActionResult | undefined, form: FormData): Promise<ActionResult> {
  const p = z.object({ id: z.string().regex(/^[a-z0-9_]+$/) }).safeParse(fields(form));
  if (!p.success) return invalid(p.error.issues);
  try {
    await assertUser();
  } catch {
    return { ok: false, error: "Your role cannot do this." };
  }
  const item = (await ui("ui_setup", setupSchema)).find((i) => i.id === p.data.id);
  if (!item?.validate) return { ok: false, error: "This item has nothing to validate from here." };
  const db = SupabaseOneDb.fromEnv();
  if (!db) return { ok: false, error: "The app's service key is not set (Setup item one_app_env)." };
  resetVaultCache();
  const [state, vault] = await Promise.all([db.tickState(), vaultSecrets(db)]);
  const verdict = await validate(item.validate, {
    settings: state.settings,
    credentials: credentialsFrom(vault),
    facts: {
      checkStatus: async (id) =>
        (await ui("ui_checks", checksSchema, { p_app: null })).find((c) => c.id === id)?.last_status ?? null,
      heartbeatOk: async (component) => {
        const h = (await ui("ui_heartbeats", heartbeatsSchema)).find((x) => x.component === component);
        return Boolean(h?.ok && !h.never_seen);
      },
    },
  });
  log("info", "setup.validate", { item: item.id, ok: verdict.ok });
  const r = await act("ui_setup_validated", { p_item: item.id, p_ok: verdict.ok, p_detail: verdict.detail }, [
    "/settings/setup",
    "/",
  ]);
  if (!r.ok) return r;
  return verdict.ok
    ? { ok: true, message: `Validated: ${verdict.detail}` }
    : { ok: false, error: `Not validated: ${verdict.detail}` };
}
