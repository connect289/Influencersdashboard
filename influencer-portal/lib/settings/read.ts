import "server-only";
// Reads one setting on the server with its schema and default. Settings are read with the service client because
// inf.setting() is not granted to signed-in users (Settings screens use inf.settings_list, which checks settings.read);
// callers decide who may act, as before.
import type { z } from "zod";
import { adminClient } from "@/lib/supabase/admin";
import { SETTINGS, type SettingKey, type SettingValue } from "./registry";

export async function readSetting<K extends SettingKey>(key: K): Promise<SettingValue<K>> {
  const def: { schema: z.ZodType; default: unknown } = SETTINGS[key];
  const { data } = await adminClient().rpc("setting", { p_key: key });
  const parsed = def.schema.safeParse(data);
  return (parsed.success ? parsed.data : def.default) as SettingValue<K>;
}
