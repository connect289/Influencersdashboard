import { maskForAi } from "../pii.ts";
import type { ToolResult } from "../read-tools.ts";

// The chat's `setting` read tool (D-139): one settings key as one.ui_settings gives it to the signed-in person, so
// the database's own role check applies and the model reads nothing the person cannot open on the Settings page (the
// Setup keys are not in that answer, and secrets live in Vault, never in a setting). It exists so that a put_setting
// card names the version it replaces: the model reads value and version here, and the card carries that version to
// one.ui_settings_put, which refuses a version that is no longer current (0039, D-137).
//
// What the model reads is masked like every tool result (maskForAi: contact details shortened, some keys left out,
// long text cut). A value that masking changed is not the stored value, and saving it back would write the masked
// form into the setting. So the version is given only with a value the model read whole; for any other, no version
// comes back and the answer says the key is changed on its Settings page.

export type SettingRow = { value: unknown; version: number; owner_only: boolean };
/** Reads one settings key as the signed-in person; null when the key is not one the Settings page lists. */
export type SettingReader = (key: string) => Promise<SettingRow | null>;

/** A value longer than this would be cut in the tool result (the engine's bound is 8,000 characters). */
const VALUE_MAX_CHARS = 6_000;

export function settingForModel(key: string, row: SettingRow | null): ToolResult {
  if (!row) return { ok: false, error: `no setting ${key} on the Settings page` };
  const stored = JSON.stringify(row.value);
  const masked = maskForAi(row.value);
  const fits = stored.length <= VALUE_MAX_CHARS;
  if (fits && JSON.stringify(masked) === stored) {
    return { ok: true, data: { key, version: row.version, owner_only: row.owner_only, value: row.value } };
  }
  return {
    ok: true,
    data: {
      key,
      owner_only: row.owner_only,
      saveable_from_chat: false,
      hint: fits
        ? `Parts of this value are masked or left out for the AI, so it cannot be saved from the chat: the person changes it on /settings/${key}.`
        : `This value is too long to read whole here, so it cannot be saved from the chat: the person reads and changes it on /settings/${key}.`,
      ...(fits ? { value: masked } : {}),
    },
  };
}
