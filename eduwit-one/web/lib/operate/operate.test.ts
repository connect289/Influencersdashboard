import { readdirSync, readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { appJobs, OPERATE, OPERATE_APPS, readiness, type OperateApp } from "./index.ts";

const must = <T>(v: T | undefined, what: string): T => {
  if (v === undefined) throw new Error(`missing ${what}`);
  return v;
};
const app = (key: string): OperateApp => must(OPERATE[key], key);

// Every id the Operate pages name must exist in the catalogue it comes from, so a renamed check, fix, test or Setup
// item cannot leave a step pointing at nothing (the same rule the influencer portal applies to its guides).

const root = new URL("../../../", import.meta.url);
const read = (p: string) => readFileSync(new URL(p, root), "utf8");
const asList = <T>(v: unknown, key: string): T[] =>
  Array.isArray(v) ? (v as T[]) : ((v as Record<string, T[]>)[key] ?? []);
const setupIds = new Set(asList<{ id: string }>(JSON.parse(read("config/setup-items.json")), "items").map((i) => i.id));
const hosts = new Set(
  Object.keys((JSON.parse(read("config/defaults.json")) as { hosts: Record<string, string> }).hosts),
);
const testIds = new Set(asList<{ id: string }>(JSON.parse(read("config/tests.json")), "tests").map((t) => t.id));
const checkIds = new Set(
  readdirSync(new URL("supabase/checks/", root))
    .filter((f) => f.endsWith(".sql"))
    .flatMap((f) => [...read(`supabase/checks/${f}`).matchAll(/^-- check: (\S+)$/gm)].map((m) => must(m[1], "match"))),
);
const fixIds = new Set(
  [...read("supabase/migrations/0019_fixes.sql").matchAll(/\('(FIX-[A-Z0-9-]+)', '(?:witty|b2b|b2c|web|one)'/g)].map(
    (m) => must(m[1], "match"),
  ),
);
const runbookSecrets = new Set(
  [...read("docs/RUNBOOK.md").matchAll(/`(one_[a-z0-9_]+)`/g)].map((m) => must(m[1], "match")),
);

describe("the Operate model", () => {
  it("covers the five apps and Eduwit One itself", () => {
    expect([...OPERATE_APPS].sort()).toEqual(["b2b", "b2c", "influencer", "one", "web", "witty"]);
    for (const key of OPERATE_APPS) expect(app(key).key).toBe(key);
  });

  it("names only Setup items, hosts, checks, fixes, tests and secrets that exist", () => {
    for (const a of Object.values(OPERATE)) {
      for (const id of a.needs) expect(setupIds, `${a.key} needs ${id}`).toContain(id);
      for (const s of a.firstTime) if (s.setup) expect(setupIds, `${a.key} step ${s.title}`).toContain(s.setup);
      for (const h of a.hosts) expect(hosts, `${a.key} host ${h}`).toContain(h);
      for (const f of a.fixes) expect(fixIds, `${a.key} fix ${f}`).toContain(f);
      for (const t of a.tests) expect(testIds, `${a.key} test ${t}`).toContain(t);
      for (const w of a.whenFires) expect(checkIds, `${a.key} check ${w.check}`).toContain(w.check);
      for (const s of a.secrets) expect(runbookSecrets, `${a.key} secret ${s} has no rotation row`).toContain(s);
    }
  });

  it("gives every check of spec §8's fixes to the app the fix acts on", () => {
    const fixApp = new Map(
      [...read("supabase/migrations/0019_fixes.sql").matchAll(/\('(FIX-[A-Z0-9-]+)', '(witty|b2b|b2c|web|one)'/g)].map(
        (m) => [must(m[1], "fix"), must(m[2], "app")],
      ),
    );
    for (const [fix, owner] of fixApp) expect(app(owner).fixes, `${fix} belongs to ${owner}`).toContain(fix);
  });

  it("picks an app's cron jobs by prefix", () => {
    const jobs = [
      { job: "b2b-outbox-tick" },
      { job: "b2c-minute" },
      { job: "inf-jobs" },
      { job: "influencer_login_attempts_purge" },
      { job: "one-tick" },
    ];
    expect(appJobs(app("b2b"), jobs).map((j) => j.job)).toEqual(["b2b-outbox-tick"]);
    expect(appJobs(app("influencer"), jobs).map((j) => j.job)).toEqual(["inf-jobs", "influencer_login_attempts_purge"]);
    expect(appJobs(app("witty"), jobs)).toEqual([]);
  });

  it("counts readiness over the Setup items the app needs", () => {
    const items = [
      { id: "n8n_api", state: { validated: false } },
      { id: "chatwoot", state: { validated: true } },
      { id: "whatsapp", state: {} },
    ];
    const r = readiness(app("witty"), items);
    expect(r).toEqual({ done: 1, total: 3, missing: ["n8n_api", "whatsapp"] });
  });
});
