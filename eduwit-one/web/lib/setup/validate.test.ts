import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { settingsSchema } from "../state.ts";
import { engineVerdict, validate } from "./validate.ts";

// Every validator a Setup item names must exist: an item whose validator is missing can never be validated, and the
// checks and tests waiting for it never switch on (phase 5 review B1).

const items = (
  JSON.parse(readFileSync(new URL("../../../config/setup-items.json", import.meta.url), "utf8")) as {
    items: Array<{ id: string; validate: string | null }>;
  }
).items;

const settings = settingsSchema.parse({
  hosts: {
    website: "https://eduwit.in",
    spark: "https://spark.eduwit.in",
    b2b_app: "https://crm.eduwit.in",
    influencer: "https://influencer.eduwit.in",
    chatwoot: "https://chat.eduwit.in",
    n8n: "https://n8n.eduwit.in",
    one: "https://one.eduwit.in",
  },
  health_paths: {},
  vendors: {
    vercel_api: "https://api.vercel.com",
    graph_api: "https://graph.facebook.com/v21.0",
    resend_api: "https://api.resend.com",
  },
  alerts: { email_from: "Eduwit One <one@eduwit.in>" },
  vercel: { team: "eduwit", projects: {} },
  chatwoot: { account_id: "1" },
  n8n: { witty_workflow_id: "w" },
  whatsapp: { waba_ids: [], alert_phone_id: null },
  witty: { expect_nurture: true, expect_learning: true },
  thresholds: {},
});

describe("Setup validators", () => {
  const kinds = [...new Set(items.map((i) => i.validate).filter((v): v is string => !!v && !v.startsWith("health:")))];

  it.each(kinds)("%s is handled, and says what is missing when nothing is configured", async (kind) => {
    const v = await validate(kind, {
      settings,
      credentials: {},
      facts: {
        checkStatus: async () => null,
        heartbeatOk: async () => false,
        testFacts: async () => null,
        aiSettings: async () => null,
        engineFacts: async () => null,
      },
    });
    expect(v.detail).not.toMatch(/nothing to validate/);
    if (!["api_schema"].includes(kind)) expect(v.ok).toBe(false);
  });

  it("covers the test items the synthetic tests need", () => {
    const byId = new Map(items.map((i) => [i.id, i.validate]));
    for (const id of [
      "test_b2b_intake_key",
      "test_partner",
      "test_whatsapp_number",
      "test_runner_user",
      "test_spark_journey",
      "ai_key",
    ]) {
      expect(byId.get(id), id).toBeTruthy();
    }
  });

  it("engine_schema passes only when every Catalogue Engine table exists, is readable and has its columns", () => {
    const table = (t: Partial<{ exists: boolean; readable: boolean; missing_columns: string[] }> = {}) => ({
      exists: true,
      readable: true,
      missing_columns: [],
      ...t,
    });
    expect(engineVerdict({ tables: { "ce.job": table(), "ce.events": table() } })).toEqual({
      ok: true,
      detail: "schema ce has the 2 tables Eduwit One reads, with their columns",
    });
    const missing = engineVerdict({
      tables: {
        "ce.job": table({ exists: false, readable: false }),
        "ce.run": table({ readable: false }),
        "ce.health": table({ missing_columns: ["message", "observed_at"] }),
      },
    });
    expect(missing.ok).toBe(false);
    expect(missing.detail).toBe(
      "the Catalogue Engine is not installed here yet: ce.job does not exist; ce.run is not readable by the database owner; ce.health lacks message, observed_at",
    );
    expect(engineVerdict({ tables: {} }).ok).toBe(false);
    expect(engineVerdict("nonsense").ok).toBe(false);
  });
});
