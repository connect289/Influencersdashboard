#!/usr/bin/env node
// Runs Lighthouse (mobile, simulated slow 4G + 4x CPU slowdown ≈ mid-range Android) on a list of paths and writes a
// JSON summary + HTML reports. Usage: node scripts/lighthouse.mjs <baseUrl> <outDir> <path,path,...>
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";

const [base = "http://localhost:3100", out = "lh", list = "/"] = process.argv.slice(2);
mkdirSync(out, { recursive: true });
const chrome = process.env.CHROME_PATH || "/opt/pw-browsers/chromium";
const rows = [];
for (const p of list.split(",")) {
  const name = p.replace(/[^a-z0-9]+/gi, "_").replace(/^_|_$/g, "") || "home";
  const file = path.join(out, name);
  execFileSync(
    "npx",
    ["lighthouse", base + p, "--quiet", "--form-factor=mobile", "--throttling-method=simulate", "--only-categories=performance,accessibility,best-practices,seo", "--output=json", "--output=html", `--output-path=${file}`, "--chrome-flags=--headless=new --no-sandbox --disable-gpu"],
    { stdio: "inherit", env: { ...process.env, CHROME_PATH: chrome } },
  );
  const r = JSON.parse(readFileSync(`${file}.report.json`, "utf8"));
  const a = r.audits;
  rows.push({
    path: p,
    performance: Math.round(r.categories.performance.score * 100),
    accessibility: Math.round(r.categories.accessibility.score * 100),
    bestPractices: Math.round(r.categories["best-practices"].score * 100),
    seo: Math.round(r.categories.seo.score * 100),
    lcp: a["largest-contentful-paint"].displayValue,
    tbt: a["total-blocking-time"].displayValue,
    cls: a["cumulative-layout-shift"].displayValue,
    fcp: a["first-contentful-paint"].displayValue,
    jsKb: Math.round((a["resource-summary"]?.details?.items?.find((i) => i.resourceType === "script")?.transferSize ?? 0) / 1024),
  });
}
writeFileSync(path.join(out, "summary.json"), JSON.stringify(rows, null, 2));
console.table(rows);
