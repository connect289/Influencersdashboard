// Every translation key used in code exists in messages/en.json, and every setting field has a label.
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { SETTING_KEYS, settingJsonSchema } from "@/lib/settings/registry";
import { STAFF_ROLES } from "@/lib/auth/permissions";
import { AGENCY_NAV, CREATOR_NAV, STAFF_NAV } from "@/lib/nav";
import {
  CONTACT_KINDS,
  CONTENT_FORMATS,
  GST_STATUSES,
  KYC_DB_ERRORS,
  KYC_FORM_ERRORS,
  PLATFORMS,
} from "@/lib/creators/schemas";
import { AGENCY_GRANTS } from "@/lib/agencies/schemas";
import en from "@/messages/en.json";

const root = join(import.meta.dirname, "..");
function files(dir: string): string[] {
  return readdirSync(dir).flatMap((f) => {
    const p = join(dir, f);
    if (statSync(p).isDirectory()) return f === "node_modules" || f.startsWith(".") ? [] : files(p);
    return /\.(ts|tsx)$/.test(f) && !f.endsWith(".test.ts") ? [p] : [];
  });
}

function has(key: string): boolean {
  let node: unknown = en;
  for (const part of key.split(".")) {
    if (typeof node !== "object" || node === null || !(part in node)) return false;
    node = (node as Record<string, unknown>)[part];
  }
  return typeof node === "string";
}

describe("messages", () => {
  const sources = ["app", "components", "lib"].flatMap((d) => files(join(root, d)));
  const keys = new Set<string>();
  for (const f of sources)
    for (const m of readFileSync(f, "utf8").matchAll(/\bt\("([a-zA-Z0-9_.]+)"/g)) keys.add(m[1] ?? "");

  it("finds keys to check", () => expect(keys.size).toBeGreaterThan(100));
  it.each([...keys])("has %s", (k) => expect(has(k)).toBe(true));

  it("labels every navigation item", () => {
    for (const i of [...STAFF_NAV, ...CREATOR_NAV, ...AGENCY_NAV]) expect(has(i.labelKey), i.labelKey).toBe(true);
  });

  it("labels every value used as a dynamic key", () => {
    const keys = [
      ...Object.values(KYC_DB_ERRORS),
      ...Object.values(KYC_FORM_ERRORS),
      ...PLATFORMS.map((p) => `platforms.${p}`),
      ...CONTENT_FORMATS.map((f) => `formats.${f}`),
      ...GST_STATUSES.map((g) => `kyc.gst.${g}`),
      ...CONTACT_KINDS.map((k) => `profile.contacts.kinds.${k}`),
      ...AGENCY_GRANTS.map((g) => `agencies.grants.${g}`),
      ...["pending", "submitted", "verified", "rejected"].map((s) => `kyc.status.${s}`),
    ];
    for (const k of keys) expect(has(k), k).toBe(true);
  });

  it("describes every role", () => {
    for (const r of STAFF_ROLES) expect(has(`roles.descriptions.${r}`)).toBe(true);
  });

  it("labels every setting field and option", () => {
    const walk = (s: Record<string, unknown>): void => {
      for (const [k, v] of Object.entries((s.properties ?? {}) as Record<string, Record<string, unknown>>)) {
        expect(has(`settingFields.${k}`), k).toBe(true);
        walk(v);
      }
      const items = s.items as Record<string, unknown> | undefined;
      if (items) walk(items);
      for (const e of (s.enum ?? []) as unknown[])
        if (typeof e === "string" && /^[a-z_]+$/.test(e)) expect(has(`settingOptions.${e}`), e).toBe(true);
      for (const a of (s.anyOf ?? []) as Record<string, unknown>[]) walk(a);
    };
    for (const key of SETTING_KEYS) walk(settingJsonSchema(key));
  });
});
