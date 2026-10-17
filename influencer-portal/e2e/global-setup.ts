import { execFileSync } from "node:child_process";
import { rmSync } from "node:fs";
import { join } from "node:path";
import { createClient } from "@supabase/supabase-js";
import { localEnv } from "./env";

/**
 * Resets the LOCAL database (all migrations from scratch), seeds it and clears Mailpit, so every run starts from the
 * same state. Set E2E_RESET=0 to skip the reset while iterating on one test.
 */
export default async function globalSetup() {
  const env = localEnv();
  const url = env.NEXT_PUBLIC_SUPABASE_URL ?? "";
  if (!/^http:\/\/(127\.0\.0\.1|localhost):\d+$/.test(url))
    throw new Error("e2e runs only against the local Supabase stack");
  // Sessions saved by staffLogin() belong to one run.
  rmSync(join(import.meta.dirname, ".auth"), { recursive: true, force: true });
  if (process.env.E2E_RESET !== "0") {
    execFileSync("node", [join(import.meta.dirname, "..", "scripts", "db.mjs"), "reset"], { stdio: "inherit" });
  }
  execFileSync("npx", ["tsx", join(import.meta.dirname, "..", "scripts", "seed.ts")], {
    stdio: "inherit",
    env: { ...process.env, ...env },
  });
  const db = createClient(url, env.SUPABASE_SERVICE_ROLE_KEY ?? "", {
    auth: { persistSession: false },
    db: { schema: "inf" },
  });
  await db.from("rate_hits").delete().neq("key", "");
  await db.from("email_codes").delete().not("id", "is", null);
  await fetch(`${process.env.MAILPIT_URL ?? "http://127.0.0.1:54424"}/api/v1/messages`, { method: "DELETE" });
}
