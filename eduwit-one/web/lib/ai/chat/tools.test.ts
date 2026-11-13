import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { ASK_TOOLS } from "../schemas.ts";
import {
  CHAT_TOOLS,
  DB_READ_TOOLS,
  SETTING_TOOL,
  toolByName,
  toolDefinition,
  toolsFor,
  type ActTool,
} from "./tools.ts";

// The tool catalogue is the chat's whole reach: every act maps to a page function the migrations grant to signed-in
// people, every read is one Ask already has, plus the one settings key the chat reads as the signed-in person
// (D-139), and the owner-only acts are not offered to an engineer.

const grants = readFileSync(new URL("../../../../supabase/migrations/0011_ui_write.sql", import.meta.url), "utf8")
  .concat(readFileSync(new URL("../../../../supabase/migrations/0019_fixes.sql", import.meta.url), "utf8"))
  .concat(readFileSync(new URL("../../../../supabase/migrations/0020_hardening.sql", import.meta.url), "utf8"))
  .concat(
    readFileSync(
      new URL("../../../../supabase/migrations/0039_settings_owner_and_versions.sql", import.meta.url),
      "utf8",
    ),
  );

const acts = CHAT_TOOLS.filter((t): t is ActTool => t.kind === "act");

describe("the tool catalogue", () => {
  it("has unique names and a JSON schema for each input", () => {
    const names = CHAT_TOOLS.map((t) => t.name);
    expect(new Set(names).size).toBe(names.length);
    for (const t of CHAT_TOOLS) {
      const d = toolDefinition(t);
      expect(d.input_schema.type).toBe("object");
      expect(d.input_schema).not.toHaveProperty("$schema");
      expect(d.description.length).toBeGreaterThan(20);
    }
  });

  it("reads what Ask reads, through the database or the app, and one settings key as the signed-in person", () => {
    const reads = CHAT_TOOLS.filter((t) => t.kind === "read").map((t) => t.name);
    expect([...reads].sort()).toEqual([...ASK_TOOLS, SETTING_TOOL].sort());
    for (const name of DB_READ_TOOLS) expect(ASK_TOOLS).toContain(name);
    expect(DB_READ_TOOLS.has("runbook")).toBe(false);
    // The service role's one.ai_tool never answers it: it is read with the person's own session (D-139).
    expect(DB_READ_TOOLS.has(SETTING_TOOL)).toBe(false);
    expect((ASK_TOOLS as readonly string[]).includes(SETTING_TOOL)).toBe(false);
    expect(toolByName(SETTING_TOOL)?.input.safeParse({ key: "thresholds" }).success).toBe(true);
    expect(toolByName(SETTING_TOOL)?.input.safeParse({ key: "one.settings; drop" }).success).toBe(false);
    expect(toolsFor("engineer").map((t) => t.name)).toContain(SETTING_TOOL);
  });

  it("saves a setting only over the version the model read (D-139)", () => {
    const put = toolByName("put_setting") as ActTool;
    const args = { key: "checks", value: { slow_ms: 6000 }, reason: "slower checks at night" };
    // A card without the version is not a card: an older one cannot be confirmed either (the arguments are parsed again).
    expect(put.input.safeParse(args).success).toBe(false);
    expect(put.input.safeParse({ ...args, expected_version: 0 }).success).toBe(false);
    expect(put.input.safeParse({ ...args, expected_version: "7" }).success).toBe(false);
    const parsed = put.input.parse({ ...args, expected_version: 7 }) as Record<string, unknown>;
    expect(put.call(parsed)).toEqual({
      fn: "ui_settings_put",
      args: { p_key: "checks", p_value: { slow_ms: 6000 }, p_reason: "slower checks at night", p_expected_version: 7 },
    });
    expect(put.summary(parsed)).toBe("Change setting checks (over version 7)");
    expect(toolDefinition(put).input_schema.required).toContain("expected_version");
    expect(put.description).toContain("expected_version");
    // The function the card calls takes that argument (0039), and compares it under the row's lock.
    expect(grants).toMatch(
      /one\.ui_settings_put\(p_key text, p_value jsonb, p_reason text, p_request_id text default null,\s+p_expected_version integer default null\)/,
    );
  });

  it("tells the model that muting a P1 is the owner's, and leaves the refusal to the database (0040, D-139)", () => {
    const mute = toolByName("mute") as ActTool;
    expect(mute.description).toMatch(/P1 check.*needs the owner/);
    // Still offered to an engineer: any other check or app is theirs to mute, and one.ui_mute decides.
    expect(mute.perm).toBe("operate");
    const m0040 = readFileSync(
      new URL("../../../../supabase/migrations/0040_owner_mutes_p1.sql", import.meta.url),
      "utf8",
    );
    expect(m0040).toContain(
      "create or replace function one.ui_mute(p_target_type text, p_target text, p_minutes integer, p_reason text, p_request_id text default null) returns jsonb",
    );
    expect(m0040).toContain("perform one.ui_require('owner');");
  });

  it("acts only through page functions the migrations grant to signed-in people", () => {
    for (const t of acts) {
      const call = t.call(sample(t));
      if ("local" in call) {
        expect(call.local).toBe("validate_setup");
        continue;
      }
      expect(call.fn).toMatch(/^ui_[a-z_]+$/);
      expect(grants).toMatch(new RegExp(`'one\\.${call.fn}\\(`));
      for (const k of Object.keys(call.args)) expect(k).toMatch(/^p_[a-z_]+$/);
      expect(t.summary(sample(t))).toMatch(/\S/);
    }
  });

  it("runs at once only a fix's dry run; everything else waits for a confirmation", () => {
    const auto = acts.filter((t) => !t.confirm).map((t) => t.name);
    // Acknowledging is a card (D-107): it stops a P1's reminders and cannot be undone from the console.
    expect(toolByName("acknowledge_incident")).toMatchObject({ confirm: true });
    // So are the acts with effects outside the console's own records (D-120): a validator's real call, deep-tier spend.
    for (const name of ["validate_setup", "rerun_deep", "regenerate_brief"]) {
      expect(toolByName(name), name).toMatchObject({ confirm: true });
    }
    expect(auto).toEqual(["dry_run_fix"]);
    for (const t of acts) if (t.risk === "high") expect(t.confirm).toBe(true);
  });

  it("has no act that adds or changes a person: people are managed on Settings → Users (D-116)", () => {
    expect(toolByName("put_user")).toBeUndefined();
    const fns = acts.map((t) => t.call(sample(t))).map((c) => ("fn" in c ? c.fn : c.local));
    expect(fns).not.toContain("ui_user_put");
  });

  it("keeps the owner-only acts from an engineer", () => {
    const engineer = toolsFor("engineer").map((t) => t.name);
    expect(engineer).not.toContain("set_fix");
    expect(engineer).toContain("acknowledge_incident");
    expect(toolsFor("owner").map((t) => t.name)).toContain("set_fix");
  });

  it("validates the arguments before anything runs", () => {
    const mute = toolByName("mute");
    expect(
      mute?.input.safeParse({ target_type: "check", target: "WITTY-04", minutes: 60, reason: "deploy" }).success,
    ).toBe(true);
    expect(mute?.input.safeParse({ target_type: "lead", target: "x", minutes: 60, reason: "deploy" }).success).toBe(
      false,
    );
    expect(
      mute?.input.safeParse({ target_type: "check", target: "WITTY-04", minutes: 99999, reason: "deploy" }).success,
    ).toBe(false);
    expect(toolByName("set_fix")?.input.safeParse({ fix_id: "drop table", reason: "x" }).success).toBe(false);
    expect(toolByName("request_secret")?.input.safeParse({ name: "one_n8n_key", item: "n8n_api" }).success).toBe(true);
    expect(toolByName("request_secret")?.input.safeParse({ name: "SUPABASE_SERVICE_ROLE_KEY" }).success).toBe(false);
  });
});

/** A valid argument object for each act, for the mapping test. */
function sample(t: ActTool): Record<string, unknown> {
  const samples: Record<string, Record<string, unknown>> = {
    acknowledge_incident: { id: 1 },
    resolve_incident: { id: 1, resolution: "fixed", note: "restarted the worker" },
    rerun_deep: { id: 1 },
    mute: { target_type: "check", target: "WITTY-04", minutes: 60, reason: "deploy window" },
    unmute: { id: 1 },
    run_test: { test_id: "T-WITTY-QUALIFY" },
    dry_run_fix: { fix_id: "FIX-N8N-RETRY", incident_id: 1 },
    set_fix: { fix_id: "FIX-N8N-RETRY", enabled: true, reason: "dry runs held for two weeks" },
    unpause_fix: { fix_id: "FIX-N8N-RETRY", reason: "the cause is fixed" },
    decide_proposal: { id: 1, decision: "approve" },
    create_proposal: {
      kind: "feature",
      app: "witty",
      title: "A clearer handoff label",
      rationale: "Counsellors miss the handoff label on busy days.",
      risk: "low",
    },
    update_check: { id: "WITTY-04", patch: { severity: "P3" }, reason: "noisy at night" },
    update_test: { id: "T-WITTY-QUALIFY", patch: { enabled: false }, reason: "number changing" },
    put_setting: {
      key: "thresholds",
      value: { catalogue_min: 45 },
      expected_version: 12,
      reason: "the cache runs every 15 minutes",
    },
    regenerate_brief: { for_date: "2026-10-28", tier: "regular" },
    validate_setup: { item: "n8n_api" },
  };
  const s = samples[t.name];
  if (!s) throw new Error(`no sample for ${t.name}`);
  const parsed = t.input.safeParse(s);
  if (!parsed.success) throw new Error(`sample for ${t.name} is invalid: ${parsed.error.message}`);
  return parsed.data as Record<string, unknown>;
}
