// Local database helper. Wraps the Supabase CLI so every command uses the same settings.
//   node scripts/db.mjs start | stop | reset | test | types
// Images are pulled from Docker Hub (SUPABASE_INTERNAL_IMAGE_REGISTRY=docker.io) because some networks block
// public.ecr.aws. This script never talks to a remote project: it refuses if SUPABASE_DB_URL or --linked is set.
import { spawnSync } from "node:child_process";
import { writeFileSync } from "node:fs";

const cmd = process.argv[2];
const env = {
  ...process.env,
  SUPABASE_INTERNAL_IMAGE_REGISTRY: process.env.SUPABASE_INTERNAL_IMAGE_REGISTRY ?? "docker.io",
};
if (process.argv.includes("--linked") || process.env.SUPABASE_DB_URL) {
  console.error("scripts/db.mjs only works against the local stack.");
  process.exit(2);
}

function run(args, opts = {}) {
  const r = spawnSync("npx", ["supabase", ...args], {
    stdio: opts.capture ? ["ignore", "pipe", "inherit"] : "inherit",
    env,
    encoding: "utf8",
  });
  if (r.status !== 0) process.exit(r.status ?? 1);
  return r.stdout ?? "";
}

switch (cmd) {
  case "start":
    run(["start"]);
    break;
  case "stop":
    run(["stop"]);
    break;
  case "reset":
    run(["db", "reset", "--local"]);
    break;
  case "test":
    {
      const r = spawnSync("node", [new URL("./test-db.mjs", import.meta.url).pathname, ...process.argv.slice(3)], {
        stdio: "inherit",
      });
      process.exit(r.status ?? 1);
    }
    break;
  case "types": {
    const out = run(["gen", "types", "typescript", "--local", "--schema", "inf"], { capture: true });
    writeFileSync(new URL("../lib/database.types.ts", import.meta.url), out);
    console.info("wrote lib/database.types.ts");
    break;
  }
  default:
    console.error("usage: node scripts/db.mjs start|stop|reset|test|types");
    process.exit(2);
}
