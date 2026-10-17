#!/usr/bin/env node
// Fails when site copy contains claims the spec forbids (spec 14: no "guaranteed job", "100% placement", "equivalent to
// regular degree" etc. unless a specific, sourced statement). Scans components, app pages and content.
import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..");
const DIRS = ["app", "components", "content"];
const BANNED = [
  /guarantee[ds]?\s+(a\s+)?(job|placement|admission|seat)/i,
  /100\s*%\s*(job|placement)/i,
  /equivalent\s+to\s+(a\s+)?regular\s+degree/i,
  /assured\s+(job|placement)/i,
  /\bbest\s+university\s+in\s+india\b/i,
  /\b(hurry|only\s+\d+\s+seats?\s+left|last\s+chance)\b/i,
  // Blanket approval claims: approvals are per university, from the catalogue (3 universities state none).
  /UGC[- ]entitled\s+(online|distance|universit|programme|program|degree|course)/i,
  /\b(all|every|only)\s+(our\s+)?(universit\w*|programmes?|programs?|degrees?)\s+(are\s+)?(ugc|aicte|naac)/i,
];
const ALLOW_FILE = /check-banned-phrases|\.test\.tsx?$/;
let failures = 0;
function walk(dir) {
  for (const f of readdirSync(dir)) {
    const p = path.join(dir, f);
    if (statSync(p).isDirectory()) {
      if (f !== "node_modules" && f !== "legacy") walk(p);
    } else if (/\.(tsx?|mdx?|json)$/.test(f) && !ALLOW_FILE.test(f)) {
      const lines = readFileSync(p, "utf8").split("\n");
      lines.forEach((line, i) => {
        for (const re of BANNED) if (re.test(line)) {
          failures++;
          console.error(`${path.relative(root, p)}:${i + 1}: banned claim (${re}): ${line.trim().slice(0, 140)}`);
        }
      });
    }
  }
}
for (const d of DIRS) walk(path.join(root, d));
if (failures) process.exit(1);
console.info("banned-phrase check: clean");
