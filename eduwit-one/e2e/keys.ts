// The run's keys, as shell exports for e2e/run.sh: the anon and service keys the app is given. The click-through signs
// the staff sessions itself, at the moment each browser signs in.
import { sign as signWith } from "./jwt.ts";

const secret = process.env.E2E_JWT_SECRET ?? "";
if (secret.length < 32) throw new Error("E2E_JWT_SECRET is not set");
const sign = (claims: Parameters<typeof signWith>[1]) => signWith(secret, claims);

const exp = Math.floor(Date.now() / 1000) + 6 * 3600;
const tokens = {
  ONE_SUPABASE_ANON_KEY: sign({ role: "anon", exp }),
  ONE_SUPABASE_SERVICE_KEY: sign({ role: "service_role", exp }),
};
for (const [k, v] of Object.entries(tokens)) console.log(`export ${k}='${v}'`);
