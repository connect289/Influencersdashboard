// Writes lib/ai/docs.generated.ts from docs/*.md (the runbook tool's source).   node scripts/gen-docs.ts [--check]
import { readFileSync, writeFileSync } from "node:fs";
import { type DocFile, docsModule } from "../lib/ai/docs-source.ts";

const read = (file: DocFile) => readFileSync(new URL(`../../docs/${file}.md`, import.meta.url), "utf8");
const target = new URL("../lib/ai/docs.generated.ts", import.meta.url);
const next = docsModule(read);

if (process.argv.includes("--check")) {
  let current = "";
  try {
    current = readFileSync(target, "utf8");
  } catch {
    // missing counts as stale
  }
  if (current !== next) {
    console.error("lib/ai/docs.generated.ts is stale: run node scripts/gen-docs.ts");
    process.exit(1);
  }
  console.warn("lib/ai/docs.generated.ts is current");
} else {
  writeFileSync(target, next);
  console.warn("wrote lib/ai/docs.generated.ts");
}
