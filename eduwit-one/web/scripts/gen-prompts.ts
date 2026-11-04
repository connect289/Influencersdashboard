// Writes lib/ai/prompts.generated.ts from lib/ai/prompts/*.md.   node scripts/gen-prompts.ts [--check]
import { readFileSync, writeFileSync } from "node:fs";
import { promptModule } from "../lib/ai/prompt-source.ts";

const read = (name: string) => readFileSync(new URL(`../lib/ai/prompts/${name}.md`, import.meta.url), "utf8");
const target = new URL("../lib/ai/prompts.generated.ts", import.meta.url);
const next = promptModule(read);

if (process.argv.includes("--check")) {
  let current = "";
  try {
    current = readFileSync(target, "utf8");
  } catch {
    // missing counts as stale
  }
  if (current !== next) {
    console.error("lib/ai/prompts.generated.ts is stale: run node scripts/gen-prompts.ts");
    process.exit(1);
  }
  console.warn("lib/ai/prompts.generated.ts is current");
} else {
  writeFileSync(target, next);
  console.warn("wrote lib/ai/prompts.generated.ts");
}
