import type { Tone } from "./badge.tsx";

// Names people read, for the keys the database uses.
export const appNames: Record<string, string> = {
  witty: "Witty",
  b2b: "B2B CRM",
  b2c: "Spark",
  web: "Website",
  influencer: "Influencer portal",
  one: "Eduwit One",
  platform: "Platform",
  catalogue: "Catalogue",
  integrity: "Integrity",
};

export const appName = (key: string) => appNames[key] ?? key;

export const alertStates: Record<string, string> = {
  pending: "alert queued",
  sent: "alerted",
  escalated_1: "reminded",
  escalated_2: "escalated",
  muted: "muted",
  suppressed: "held by a storm",
  digest: "in the P2 digest",
  none: "dashboard only",
};

export const riskTone: Record<string, Tone> = { high: "p1", medium: "p2", low: "p3" };

// Fixes (0019).
export const fixModes: Record<string, { label: string; tone: Tone; hint: string }> = {
  act: { label: "acts", tone: "neutral", hint: "Runs in the database with the fixer's rights." },
  app: {
    label: "acts from the app",
    tone: "neutral",
    hint: "The app makes the call (n8n, or the Spark check), the database records it.",
  },
  approve: {
    label: "owner approves",
    tone: "accent",
    hint: "Opens a proposal; your approval runs the app's own function under your session.",
  },
  propose: {
    label: "proposes only",
    tone: "off",
    hint: "Cannot act without a change to the app; opens a proposal that says which.",
  },
};

export const actionSteps: Record<string, string> = {
  dry_run: "dry run",
  before: "about to act",
  after: "acted",
  skip: "did nothing",
  verify: "verified",
};

/** One line on what an action row says it did, from its result (never its target's ids). */
export function actionSummary(step: string, status: string, result: unknown): string {
  const r = (result && typeof result === "object" ? result : {}) as Record<string, unknown>;
  const text = (v: unknown) => (typeof v === "string" ? v : null);
  if (step === "dry_run") return `Would ${text(r.would) ?? "act"}${r.why_dry ? ` (dry: ${text(r.why_dry)})` : ""}.`;
  if (step === "skip")
    return `Did nothing: ${text(r.reason) ?? "skipped"}${r.proposal ? `, proposal #${String(r.proposal)}` : ""}.`;
  if (step === "verify")
    return r.held === true ? "Held." : `Did not hold${r.to ? `: incident now ${text(r.to)}` : ""}.`;
  if (step === "before") return text(r.waiting) ? `Waiting for ${text(r.waiting)}.` : "About to act.";
  if (r.proposal)
    return `Opened proposal #${String(r.proposal)}${r.waiting ? `, waiting for ${text(r.waiting)}` : ""}.`;
  if (status === "failed") return `Failed: ${text(r.error) ?? "see the result"}.`;
  return "Done.";
}
