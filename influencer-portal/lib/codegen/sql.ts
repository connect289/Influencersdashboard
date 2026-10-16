// Builds the generated SQL migrations from the TypeScript sources of truth. Pure: no I/O.
// Each output starts with `-- generated: <kind> sha256=<hash>`; codegen.test.ts fails when the newest migration of a
// kind carries a different hash than the current sources (someone changed the matrix or registry without running
// `npm run gen:sql`).
import { createHash } from "node:crypto";
import { PERMISSIONS, ROLE_GRANTS, STAFF_ROLES, type Permission } from "@/lib/auth/permissions";
import { SETTINGS, SETTING_KEYS, settingJsonSchema } from "@/lib/settings/registry";

export type GeneratedKind = "permission-matrix" | "settings-definitions";

export function sqlString(value: string): string {
  return `'${value.replace(/'/g, "''")}'`;
}

function jsonLiteral(value: unknown): string {
  return `${sqlString(JSON.stringify(value))}::jsonb`;
}

function withHeader(kind: GeneratedKind, body: string): { sql: string; hash: string } {
  const hash = createHash("sha256").update(body).digest("hex");
  const header = [
    `-- generated: ${kind} sha256=${hash}`,
    "-- DO NOT EDIT. Produced by `npm run gen:sql` from lib/auth/permissions.ts and lib/settings/registry.ts.",
    "",
  ].join("\n");
  return { sql: header + body, hash };
}

export function permissionMatrixSql(): { sql: string; hash: string } {
  const perms = Object.entries(PERMISSIONS) as [Permission, { area: string; label: string }][];
  const permValues = perms
    .map(([k, v]) => `  (${sqlString(k)}, ${sqlString(v.area)}, ${sqlString(v.label)})`)
    .join(",\n");
  const grants = STAFF_ROLES.flatMap((role) =>
    [...new Set(ROLE_GRANTS[role])].sort().map((p) => `  (${sqlString(role)}, ${sqlString(p)})`),
  );
  const body = [
    "insert into inf.permissions (key, area, label) values",
    permValues,
    "on conflict (key) do update set area = excluded.area, label = excluded.label;",
    "",
    "create temporary table _grants (role text, permission text) on commit drop;",
    "insert into _grants (role, permission) values",
    grants.join(",\n") + ";",
    "",
    "delete from inf.role_permissions rp where not exists (select 1 from _grants g where g.role = rp.role and g.permission = rp.permission);",
    "insert into inf.role_permissions (role, permission) select role, permission from _grants on conflict do nothing;",
    `delete from inf.permissions where key not in (${perms.map(([k]) => sqlString(k)).join(", ")});`,
    "",
  ].join("\n");
  return withHeader("permission-matrix", body);
}

export function settingsDefinitionsSql(): { sql: string; hash: string } {
  const rows = SETTING_KEYS.map((key) => {
    const d = SETTINGS[key];
    const parsed = d.schema.safeParse(d.default);
    if (!parsed.success) throw new Error(`Default for ${key} does not match its schema: ${parsed.error.message}`);
    const confirmation = "needsConfirmation" in d && d.needsConfirmation ? sqlString(d.needsConfirmation) : "null";
    return `  (${[sqlString(key), sqlString(d.group), sqlString(d.label), sqlString(d.description), jsonLiteral(settingJsonSchema(key)), jsonLiteral(d.default), sqlString(d.edit), confirmation].join(", ")})`;
  });
  const body = [
    "insert into inf.setting_definitions (key, grp, label, description, json_schema, default_value, edit_permission, needs_confirmation) values",
    rows.join(",\n"),
    "on conflict (key) do update set grp = excluded.grp, label = excluded.label, description = excluded.description,",
    "  json_schema = excluded.json_schema, default_value = excluded.default_value, edit_permission = excluded.edit_permission,",
    "  needs_confirmation = excluded.needs_confirmation, updated_at = now();",
    "",
    `delete from inf.setting_definitions where key not in (${SETTING_KEYS.map(sqlString).join(", ")});`,
    "",
  ].join("\n");
  return withHeader("settings-definitions", body);
}

export const GENERATORS: Record<GeneratedKind, () => { sql: string; hash: string }> = {
  "permission-matrix": permissionMatrixSql,
  "settings-definitions": settingsDefinitionsSql,
};

/** The hash recorded in the newest migration of a kind (file names sort by timestamp). */
export function latestRecordedHash(kind: GeneratedKind, files: { name: string; content: string }[]): string | null {
  const marker = new RegExp(`^-- generated: ${kind} sha256=([0-9a-f]{64})`, "m");
  const hits = files.filter((f) => marker.test(f.content)).sort((a, b) => a.name.localeCompare(b.name));
  const last = hits.at(-1);
  return last ? (marker.exec(last.content)?.[1] ?? null) : null;
}
