// Writes .env.local for CI from the running local Supabase stack (`supabase status`). Never used with real projects.
import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";

const status = JSON.parse(
  execFileSync("npx", ["supabase", "status", "-o", "json"], { encoding: "utf8" }),
);
const lines = {
  NEXT_PUBLIC_SUPABASE_URL: status.API_URL,
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: status.PUBLISHABLE_KEY,
  SUPABASE_SERVICE_ROLE_KEY: status.SECRET_KEY,
  NEXT_PUBLIC_SITE_URL: "http://localhost:3200",
  INF_INTERNAL_API_KEY: "ci-internal-key-0123456789abcdef0123456789abcdef",
  NEXT_PUBLIC_AUTH_GOOGLE: "off",
  LIVE_MODE: "off",
  LEAD_SYNC: "on",
  EMAIL_PROVIDER: "smtp",
  SMTP_HOST: "127.0.0.1",
  SMTP_PORT: "54425",
  SMTP_SECURE: "off",
  EMAIL_FROM: '"Eduwit Creators <creators@eduwit.in>"',
  WHATSAPP_PROVIDER: "mock",
};
writeFileSync(
  new URL("../.env.local", import.meta.url),
  Object.entries(lines)
    .map(([k, v]) => `${k}=${v}`)
    .join("\n") + "\n",
);
console.info("wrote .env.local for the local stack");
