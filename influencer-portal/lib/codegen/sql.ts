// Builds the generated SQL migrations from the TypeScript sources of truth. Pure: no I/O.
// Each output starts with `-- generated: <kind> sha256=<hash>`; codegen.test.ts fails when the newest migration of a
// kind carries a different hash than the current sources (someone changed the matrix or registry without running
// `npm run gen:sql`).
import { createHash } from "node:crypto";
import { PERMISSIONS, ROLE_GRANTS, STAFF_ROLES, type Permission } from "@/lib/auth/permissions";
import { z } from "zod";
import { PRESET_KEYS, SYSTEM_PRESETS } from "@/lib/compensation/presets";
import { compConfig } from "@/lib/compensation/schema";
import { DEFAULT_STAGE_RULES } from "@/lib/attribution/stage-rules";
import { docFromText } from "@/lib/contracts/doc";
import { DEFAULT_TEMPLATE, SEED_CLAUSES } from "@/lib/contracts/library";
import { SETTINGS, SETTING_KEYS, settingJsonSchema } from "@/lib/settings/registry";

export type GeneratedKind =
  | "permission-matrix"
  | "settings-definitions"
  | "comp-config-schema"
  | "deal-presets"
  | "clause-library"
  | "stage-mappings";

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
    "-- DO NOT EDIT. Produced by `npm run gen:sql` from lib/auth/permissions.ts, lib/settings/registry.ts,",
    "-- lib/compensation/schema.ts, lib/compensation/presets.ts and lib/contracts/library.ts.",
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
    if (!parsed.success)
      throw new Error(`Default for ${key} does not match its schema: ${parsed.error.message}`);
    const confirmation =
      "needsConfirmation" in d && d.needsConfirmation ? sqlString(d.needsConfirmation) : "null";
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
    "-- Saved values follow the current shape: new fields take their default, removed fields are dropped.",
    "update inf.settings s",
    "   set value = (select coalesce(jsonb_object_agg(k, coalesce(s.value -> k, d.default_value -> k)), '{}'::jsonb)",
    "                  from jsonb_object_keys(d.default_value) k)",
    "  from inf.setting_definitions d",
    " where d.key = s.key and jsonb_typeof(s.value) = 'object' and jsonb_typeof(d.default_value) = 'object'",
    "   and not (s.value ?& array(select jsonb_object_keys(d.default_value))",
    "            and d.default_value ?& array(select jsonb_object_keys(s.value)));",
    "",
  ].join("\n");
  return withHeader("settings-definitions", body);
}

/** JSON Schema of a deal version's compensation config (D-05). Structural checks only; the reconciliation rules
 * (milestones add up, ids unique, references exist) are re-checked by the hand-written inf.comp_config_errors(). */
export function compConfigSchemaJson(): Record<string, unknown> {
  const schema = z.toJSONSchema(compConfig, {
    target: "draft-2020-12",
    io: "output",
    unrepresentable: "throw",
    reused: "inline",
  }) as Record<string, unknown>;
  delete schema.$schema;
  return schema;
}

export function compConfigSchemaSql(): { sql: string; hash: string } {
  const body = [
    "create or replace function inf.comp_config_schema() returns jsonb",
    "language sql immutable set search_path = '' as $$",
    `  select ${jsonLiteral(compConfigSchemaJson())};`,
    "$$;",
    "",
  ].join("\n");
  return withHeader("comp-config-schema", body);
}

/** The system presets (spec 6.2) as rows of inf.deal_presets, keyed so later changes update them in place. */
export function dealPresetsSql(): { sql: string; hash: string } {
  const rows = PRESET_KEYS.map((key) => {
    const p = SYSTEM_PRESETS[key];
    return `  (${sqlString(key)}, ${sqlString(p.name)}, ${sqlString(p.description)}, ${jsonLiteral(p.config)}, true)`;
  });
  const body = [
    "insert into inf.deal_presets (key, name, description, comp_config, is_system) values",
    rows.join(",\n"),
    "on conflict (key) do update set name = excluded.name, description = excluded.description,",
    "  comp_config = excluded.comp_config, is_system = true, archived_at = null;",
    "",
    `delete from inf.deal_presets where is_system and key not in (${PRESET_KEYS.map(sqlString).join(", ")});`,
    "",
  ].join("\n");
  return withHeader("deal-presets", body);
}

/**
 * The seed clause library and default template (spec 8.1). Insert-only: once seeded, the library belongs to staff
 * (edits create new versions), so later changes to the seed never overwrite it.
 */
export function clauseLibrarySql(): { sql: string; hash: string } {
  const clauses = SEED_CLAUSES.map(
    (c) =>
      `  (${sqlString(c.key)}, ${sqlString(c.category)}, ${sqlString(c.title)}, ${jsonLiteral(docFromText(c.body))}, ${String(c.required)}, ${String(c.negotiable)}, ${String(c.locked)}, ${sqlString(`{${c.deal_types.join(",")}}`)}::text[])`,
  );
  const order = DEFAULT_TEMPLATE.clauses.map(
    (c, i) =>
      `  (${sqlString(c.key)}, ${String(i)}, ${c.condition === null ? "null" : sqlString(c.condition)})`,
  );
  const body = [
    "create temporary table _seed (key text, category text, title text, body jsonb, required boolean, negotiable boolean, locked boolean, deal_types text[]) on commit drop;",
    "insert into _seed values",
    clauses.join(",\n") + ";",
    "insert into inf.clauses (key, category, deal_types) select key, category, deal_types from _seed on conflict (key) do nothing;",
    "insert into inf.clause_versions (clause_id, version, title, body, required, negotiable, locked)",
    "select c.id, 1, s.title, s.body, s.required, s.negotiable, s.locked from _seed s join inf.clauses c on c.key = s.key",
    "on conflict (clause_id, version) do nothing;",
    "",
    "insert into inf.contract_templates (key, name, description, title, header, footer, is_default)",
    `select ${sqlString(DEFAULT_TEMPLATE.key)}, ${sqlString(DEFAULT_TEMPLATE.name)}, ${sqlString(DEFAULT_TEMPLATE.description)}, ${sqlString(DEFAULT_TEMPLATE.title)},`,
    `       ${jsonLiteral(docFromText(DEFAULT_TEMPLATE.header))}, ${jsonLiteral(docFromText(DEFAULT_TEMPLATE.footer))},`,
    "       not exists (select 1 from inf.contract_templates where is_default and archived_at is null)",
    `where not exists (select 1 from inf.contract_templates where key = ${sqlString(DEFAULT_TEMPLATE.key)});`,
    "insert into inf.template_clauses (template_id, clause_id, position, condition)",
    "select t.id, c.id, o.position, o.condition",
    "  from (values",
    order.join(",\n"),
    "  ) as o(key, position, condition)",
    "  join inf.clauses c on c.key = o.key",
    `  join inf.contract_templates t on t.key = ${sqlString(DEFAULT_TEMPLATE.key)}`,
    " where not exists (select 1 from inf.template_clauses x where x.template_id = t.id)",
    "on conflict do nothing;",
    "",
  ].join("\n");
  return withHeader("clause-library", body);
}

/** The default creator-stage rules, inserted once; later edits happen in the database (Super Admin). */
export function stageMappingsSql(): { sql: string; hash: string } {
  const rows = DEFAULT_STAGE_RULES.map(
    (r) =>
      `  (${String(r.priority)}, ${jsonLiteral(r.conditions)}, ${r.creator_stage === null ? "null" : sqlString(r.creator_stage)}, ${r.reason_category === null ? "null" : sqlString(r.reason_category)}, ${r.flag === null ? "null" : sqlString(r.flag)})`,
  );
  const body = [
    "insert into inf.stage_mappings (priority, conditions, creator_stage, reason_category, flag)",
    "select * from (values",
    rows.join(",\n"),
    ") as v(priority, conditions, creator_stage, reason_category, flag)",
    "where not exists (select 1 from inf.stage_mappings);",
    "",
  ].join("\n");
  return withHeader("stage-mappings", body);
}

export const GENERATORS: Record<GeneratedKind, () => { sql: string; hash: string }> = {
  "permission-matrix": permissionMatrixSql,
  "settings-definitions": settingsDefinitionsSql,
  "comp-config-schema": compConfigSchemaSql,
  "deal-presets": dealPresetsSql,
  "clause-library": clauseLibrarySql,
  "stage-mappings": stageMappingsSql,
};

/** The hash recorded in the newest migration of a kind (file names sort by timestamp). */
export function latestRecordedHash(
  kind: GeneratedKind,
  files: { name: string; content: string }[],
): string | null {
  const marker = new RegExp(`^-- generated: ${kind} sha256=([0-9a-f]{64})`, "m");
  const hits = files
    .filter((f) => marker.test(f.content))
    .sort((a, b) => a.name.localeCompare(b.name));
  const last = hits.at(-1);
  return last ? (marker.exec(last.content)?.[1] ?? null) : null;
}
