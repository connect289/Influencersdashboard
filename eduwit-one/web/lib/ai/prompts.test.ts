import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { TASK_KINDS } from "./models.ts";
import { PROMPT_NAMES, promptModule } from "./prompt-source.ts";
import { PROMPTS } from "./prompts.generated.ts";

// The prompts live as markdown (spec §11); the app ships the generated module. A stale module would stamp calls with a
// version that does not match the text sent.

const read = (name: string) => readFileSync(new URL(`./prompts/${name}.md`, import.meta.url), "utf8");

describe("prompts", () => {
  it("has one prompt per task kind", () => {
    expect([...PROMPT_NAMES].sort()).toEqual([...TASK_KINDS].sort());
  });

  it("prompts.generated.ts matches the markdown (node scripts/gen-prompts.ts)", () => {
    expect(readFileSync(new URL("./prompts.generated.ts", import.meta.url), "utf8")).toBe(promptModule(read));
  });

  it("stamps each prompt with its kind and a hash", () => {
    for (const name of PROMPT_NAMES) expect(PROMPTS[name].version).toMatch(new RegExp(`^${name}@[0-9a-f]{10}$`));
  });
});
