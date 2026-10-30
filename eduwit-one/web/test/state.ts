import { readFileSync } from "node:fs";
import type { OneDb, SignInEntry } from "@/lib/db.ts";
import { settingsSchema, type Report, type TickState } from "@/lib/state.ts";

// A tick state built from the same config files that seed one.settings (D-015), and a fake database that records
// what the runner writes.
const read = (p: string) =>
  JSON.parse(readFileSync(new URL(`../../config/${p}`, import.meta.url), "utf8")) as Record<string, never>;
const defaults = read("defaults.json");
const settings = read("settings.json");

const check = (id: string, enabled: boolean, disabled_reason: string | null): TickState["checks"][number] => ({
  id,
  enabled,
  disabled_reason,
  cadence_s: 60,
  last_ran_at: null,
});

export function tickState(overrides: Partial<TickState> = {}): TickState {
  return {
    now: new Date().toISOString(),
    settings: settingsSchema.parse({
      hosts: defaults.hosts,
      health_paths: defaults.health_paths,
      vendors: defaults.vendors,
      vercel: defaults.vercel,
      chatwoot: defaults.chatwoot,
      n8n: settings.n8n,
      whatsapp: settings.whatsapp,
      witty: settings.witty,
      thresholds: settings.thresholds,
      alerts: settings.alerts,
    }),
    setup: {},
    checks: [
      ...["WEB-02", "INF-04", "WEB-07", "WITTY-05"].map((id) => check(id, true, null)),
      ...["WITTY-02", "WITTY-08"].map((id) => check(id, false, "setup:n8n_api")),
    ],
    heartbeats: [],
    ...overrides,
  };
}

export class FakeDb implements OneDb {
  reports: Report[] = [];
  escalations: Array<{ conversation_id: number; account_id: number; escalated_at: string }> = [];
  state: TickState;

  constructor(state: TickState) {
    this.state = state;
  }

  async tickState() {
    return this.state;
  }

  async report(report: Report) {
    this.reports.push(report);
    return { heartbeats: report.heartbeats.length, results: report.results.length };
  }

  async wittyEscalations() {
    return this.escalations;
  }

  async watchdog() {
    return { tick_age_s: 10, app_age_s: 20, delivery_wait_s: null };
  }

  deliveries: unknown[] = [];
  finished: Array<{ id: number; ok: boolean; error: string | null; providerId: string | null }> = [];

  async claimDeliveries() {
    const out = this.deliveries;
    this.deliveries = [];
    return out;
  }

  async finishDelivery(id: number, ok: boolean, error: string | null, providerId: string | null) {
    this.finished.push({ id, ok, error, providerId });
    return ok ? "sent" : "retry";
  }

  secrets: Record<string, string> = {};
  codes: Array<{ userId: string; sessionId: string }> = [];
  signIns: SignInEntry[] = [];

  async appSecrets() {
    return this.secrets;
  }

  async authIssueCode(userId: string, sessionId: string) {
    this.codes.push({ userId, sessionId });
    return "123456";
  }

  async authRecord(entry: SignInEntry) {
    this.signIns.push(entry);
  }

  validations: Array<{ item: string; ok: boolean; actor: string }> = [];

  async setupValidated(item: string, ok: boolean, _detail: string, actor: string) {
    this.validations.push({ item, ok, actor });
    return 0;
  }

  engineFacts: unknown = { tables: {} };

  async setupEngineFacts() {
    return this.engineFacts;
  }
}
