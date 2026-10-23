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
