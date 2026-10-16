import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { GENERATORS, latestRecordedHash, sqlString, type GeneratedKind } from "./sql";

const dir = join(import.meta.dirname, "..", "..", "supabase", "migrations");
const files = readdirSync(dir).filter((f) => f.endsWith(".sql")).map((name) => ({ name, content: readFileSync(join(dir, name), "utf8") }));

describe("generated SQL", () => {
  for (const kind of Object.keys(GENERATORS) as GeneratedKind[]) {
    it(`${kind}: the newest migration matches the current sources (run npm run gen:sql if this fails)`, () => {
      expect(latestRecordedHash(kind, files)).toBe(GENERATORS[kind]().hash);
    });
  }

  it("escapes quotes in SQL strings", () => {
    expect(sqlString("it's")).toBe("'it''s'");
  });

  it("is deterministic", () => {
    expect(GENERATORS["permission-matrix"]().sql).toBe(GENERATORS["permission-matrix"]().sql);
  });
});
