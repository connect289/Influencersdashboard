import { describe, expect, it } from "vitest";
import { fixtures } from "./index.ts";
import { RealAppHealthClient } from "./app-health.ts";
import { RealChatwootClient } from "./chatwoot.ts";
import { RealVercelClient } from "./vercel.ts";

// Contract tests (spec standard 2): the Mock side always runs (the fixtures parse with the Real client's schemas at
// import); the Real side runs only with ONE_CONTRACT=1 and the credential present, as the Setup page's validate button
// does. A fixture written from documentation is listed until a real response replaces it.

const live = process.env.ONE_CONTRACT === "1";
const env = (...names: string[]) => names.map((n) => process.env[n]?.trim()).find(Boolean);

describe("fixtures", () => {
  it("lists exactly the fixtures still waiting for a real recording", () => {
    const pending = Object.entries(fixtures)
      .filter(([, f]) => !f.meta.recorded)
      .map(([name]) => name)
      .sort();
    expect(pending).toEqual(["email", "n8n", "whatsapp"]);
  });
});

describe.skipIf(!live)("real clients (ONE_CONTRACT=1)", () => {
  it("app health answers like its fixture", async () => {
    const r = await new RealAppHealthClient().health("https://eduwit.in/api/health", "json_ok");
    expect(typeof r.ok).toBe("boolean");
    expect(r.status).toBeGreaterThan(0);
  });

  it.skipIf(!env("ONE_VERCEL_TOKEN", "VERCEL_TOKEN"))("vercel lists deployments in the fixture's shape", async () => {
    const c = new RealVercelClient("https://api.vercel.com", env("ONE_VERCEL_TOKEN", "VERCEL_TOKEN") as string);
    const d = await c.deployments("eduwit-website", "eduwit");
    expect(Array.isArray(d.deployments)).toBe(true);
  });

  it.skipIf(!env("ONE_CHATWOOT_TOKEN", "CHATWOOT_API_TOKEN"))("chatwoot answers inboxes and the summary", async () => {
    const c = new RealChatwootClient(
      "https://chat.eduwit.in",
      env("ONE_CHATWOOT_TOKEN", "CHATWOOT_API_TOKEN") as string,
    );
    expect(await c.inboxCount("1")).toBeGreaterThanOrEqual(0);
  });
});
