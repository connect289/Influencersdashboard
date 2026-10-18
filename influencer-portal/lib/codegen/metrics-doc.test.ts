import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import messages from "@/messages/en.json";
import { METRIC_IDS } from "@/lib/analytics/metrics";
import { metricsMarkdown } from "./metrics-doc";

describe("docs/METRICS.md", () => {
  it("matches the metric registry and messages (run npm run gen:sql if this fails)", () => {
    const file = join(import.meta.dirname, "..", "..", "docs", "METRICS.md");
    expect(readFileSync(file, "utf8")).toBe(metricsMarkdown());
  });

  it("has a label and a definition for every metric, and nothing extra", () => {
    const msgs = messages.analytics.metrics as Record<string, { label?: string; definition?: string }>;
    expect(Object.keys(msgs).sort()).toEqual([...METRIC_IDS].sort());
    for (const id of METRIC_IDS) {
      expect(msgs[id]?.label, id).toBeTruthy();
      expect(msgs[id]?.definition, id).toBeTruthy();
    }
  });
});
