/* eslint-disable no-console -- a command-line report: the table and the misses go to stdout. */
// The AI eval (spec §11): 30 incidents (classify and triage) and 10 Ask questions through the real worker, graded
// deterministically, with cost and latency per tier.
//   npm run ai:eval                          offline: the reference answerer, proves the harness (spends nothing)
//   npm run ai:eval -- --live --yes          Claude, on the regular tier (the owner's choice: the cheapest useful run)
//   options: --tier quick|regular|deep|all  --out results.json
// The key comes from ONE_ANTHROPIC_API_KEY (or .env.local), never from anything else. A live run prints its
// worst-case cost first and spends nothing without --yes.
import { readFileSync, writeFileSync } from "node:fs";
import { AnthropicModelClient, type ModelClient } from "../lib/ai/client.ts";
import { INCIDENTS, QUESTIONS } from "../lib/ai/eval/fixtures.ts";
import { ReferenceClient, runEval, summarise, type TierReport } from "../lib/ai/eval/run.ts";
import { aiSettingsSchema, route, TIERS, worstCaseInr, type Tier } from "../lib/ai/models.ts";
import { MAX_TOKENS } from "../lib/ai/schemas.ts";

const argv = process.argv.slice(2);
const flag = (name: string) => argv.includes(`--${name}`);
const opt = (name: string) => {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 ? argv[i + 1] : undefined;
};

const raw = (
  JSON.parse(readFileSync(new URL("../../config/settings.json", import.meta.url), "utf8")) as {
    ai: Record<string, unknown>;
  }
).ai;
const ai = aiSettingsSchema.parse(raw);
const live = flag("live");
// Offline every tier runs (it costs nothing); live, the regular tier unless --tier says otherwise.
const tierArg = opt("tier") ?? (live ? "regular" : "all");
const tiers: Tier[] = tierArg === "all" ? [...TIERS] : [tierArg as Tier];
const key = process.env.ONE_ANTHROPIC_API_KEY?.trim();

const plan: Array<{ tier: Tier; client: ModelClient; label: string }> = [];
for (const tier of tiers) {
  const r = route(ai, "triage", tier);
  if (!live) {
    plan.push({
      tier,
      client: new ReferenceClient(),
      label: "reference (offline)",
    });
    continue;
  }
  if ("error" in r) {
    console.log(`${tier}: skipped: ${r.detail}`);
    continue;
  }
  if (r.tier !== tier) {
    console.log(`${tier}: skipped: no model of its own (falls back to ${r.tier})`);
    continue;
  }
  if (!key) {
    console.log(`${tier}: skipped: ONE_ANTHROPIC_API_KEY is not set`);
    continue;
  }
  const client = new AnthropicModelClient(key);
  // Worst case: every incident's two tasks and every question's three rounds at their whole output allowance.
  const perIncident =
    worstCaseInr(r.price, 12_000, MAX_TOKENS.classify, ai.usd_inr) +
    worstCaseInr(r.price, 12_000, MAX_TOKENS.triage, ai.usd_inr);
  const perQuestion =
    2 * worstCaseInr(r.price, 20_000, MAX_TOKENS.ask_round, ai.usd_inr) +
    worstCaseInr(r.price, 40_000, MAX_TOKENS.ask, ai.usd_inr);
  const worst = INCIDENTS.length * perIncident + QUESTIONS.length * perQuestion;
  console.log(`${tier}: ${r.model}, worst case ₹${worst.toFixed(0)} (a typical run costs a small fraction of it)`);
  plan.push({ tier, client, label: r.model });
}

if (live && !flag("yes")) {
  console.log("\nNothing was spent. Run again with --yes to call the models.");
  process.exit(0);
}

const reports: TierReport[] = [];
for (const p of plan) {
  process.stdout.write(`\n${p.tier} (${p.label}) `);
  reports.push(
    await runEval(ai, p.tier, p.client, (s) => process.stdout.write(s.score === 1 ? "." : s.filed ? "~" : "x")),
  );
}
console.log("\n");

const pct = (x: number) => `${Math.round(x * 100)}%`;
const rows = reports.map(summarise);
console.table(
  rows.map((s) => ({
    tier: s.tier,
    model: s.model,
    filed: `${s.filed}/${s.items}`,
    classify: pct(s.classify),
    triage: pct(s.triage),
    ask: pct(s.ask),
    overall: pct(s.overall),
    leaks: s.leaks,
    "cost USD": s.costUsd.toFixed(4),
    "cost ₹": s.costInr.toFixed(2),
    "p50 ms": s.p50LatencyMs,
  })),
);
for (const r of reports) {
  const misses = r.items.filter((i) => i.score < 1 || i.leaks.length);
  for (const m of misses.slice(0, 15)) {
    const failed = Object.entries(m.checks)
      .filter(([, ok]) => !ok)
      .map(([k]) => k);
    console.log(
      `${r.tier} ${m.id} ${m.kind}: ${m.error ?? `missed ${failed.join(", ")}`}${m.leaks.length ? `; LEAKED ${m.leaks.length}` : ""}`,
    );
  }
}
if (!live)
  console.log(
    "Offline: the reference answerer scores 100% by construction; this proves the harness and the mask, not a model.",
  );
const out = opt("out");
if (out) {
  writeFileSync(out, JSON.stringify({ at: new Date().toISOString(), live, summary: rows, reports }, null, 1));
  console.log(`wrote ${out}`);
}
if (rows.some((s) => s.leaks > 0)) process.exit(2);
