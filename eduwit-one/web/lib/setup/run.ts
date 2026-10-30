import "server-only";
import { SupabaseAiDb } from "../ai/db.ts";
import { credentialsFrom, resetVaultCache, vaultSecrets } from "../clients/credentials.ts";
import { SupabaseOneDb } from "../db.ts";
import { bootEnv } from "../env.ts";
import { log } from "../log.ts";
import { readSettings, settingsSchema } from "../state.ts";
import { SupabaseTestsDb } from "../tests/db.ts";
import { ui } from "../ui/api.ts";
import { checksSchema, heartbeatsSchema, setupSchema } from "../ui/schemas.ts";
import { parseTestFacts, validate, type Verdict } from "./validate.ts";

// A Setup item's validator, run on the server with the real client and recorded by the app (spec §15): the Setup page's
// button and the command centre's validate_setup act share it.

export async function runValidate(itemId: string, actor: string): Promise<Verdict> {
  if (!/^[a-z0-9_]+$/.test(itemId)) return { ok: false, detail: "that is not a Setup item id" };
  const item = (await ui("ui_setup", setupSchema)).find((i) => i.id === itemId);
  if (!item) return { ok: false, detail: `there is no Setup item ${itemId}` };
  if (!item.validate) return { ok: false, detail: "this item has nothing to validate from here" };
  const db = SupabaseOneDb.fromEnv();
  if (!db) return { ok: false, detail: "the app's service key is not set (Setup item one_app_env)" };
  resetVaultCache();
  const [state, vault] = await Promise.all([db.tickState(), vaultSecrets(db)]);
  // The validators read across the settings; a bad key is named here instead of failing inside a probe (F6).
  const settings = readSettings(settingsSchema, state.settings);
  if (!settings.ok) return { ok: false, detail: `fix the settings first: ${settings.error}` };
  const verdict = await validate(item.validate, {
    settings: settings.value,
    credentials: credentialsFrom(vault),
    facts: {
      checkStatus: async (id) =>
        (await ui("ui_checks", checksSchema, { p_app: null })).find((c) => c.id === id)?.last_status ?? null,
      heartbeatOk: async (component) => {
        const h = (await ui("ui_heartbeats", heartbeatsSchema)).find((x) => x.component === component);
        return Boolean(h?.ok && !h.never_seen);
      },
      testFacts: async () => {
        const tests = SupabaseTestsDb.fromEnv();
        return tests ? parseTestFacts(await tests.setupFacts()) : null;
      },
      aiSettings: async () => (await SupabaseAiDb.fromEnv()?.aiSettings()) ?? null,
      engineFacts: async () => await db.setupEngineFacts(),
    },
    supabase: { url: bootEnv().ONE_SUPABASE_URL, anonKey: bootEnv().ONE_SUPABASE_ANON_KEY },
  });
  log("info", "setup.validate", { item: item.id, ok: verdict.ok });
  // Recorded by the app with the service role, so only a probe this server ran can mark an item verified (0011).
  try {
    await db.setupValidated(item.id, verdict.ok, verdict.detail, actor, crypto.randomUUID());
  } catch (e) {
    log("error", "setup.record_failed", { item: item.id, error: e instanceof Error ? e.message : "error" });
    return { ok: false, detail: "the result could not be recorded; try again" };
  }
  return verdict;
}
