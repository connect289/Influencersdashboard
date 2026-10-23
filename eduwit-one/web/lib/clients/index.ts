import { z } from "zod";
import { secretEnv } from "../env.ts";
import type { Settings } from "../state.ts";
import { appHealthFixture, MockAppHealthClient, RealAppHealthClient } from "./app-health.ts";
import {
  chatwootInboxesFixture,
  chatwootLabelsFixture,
  chatwootSummaryFixture,
  MockChatwootClient,
  RealChatwootClient,
} from "./chatwoot.ts";
import { MockN8nClient, n8nExecutionsFixture, n8nWorkflowFixture, RealN8nClient } from "./n8n.ts";
import { emailSentFixture, MockEmailClient, RealEmailClient } from "./email.ts";
import type { Credentials } from "./credentials.ts";
import type { Clients } from "./types.ts";
import { MockVercelClient, RealVercelClient, vercelDeploymentsFixture } from "./vercel.ts";
import { MockWhatsAppClient, RealWhatsAppClient, whatsappPhoneFixture } from "./whatsapp.ts";
import appHealthLive from "./fixtures/app-health/live.json" with { type: "json" };
import chatwootLive from "./fixtures/chatwoot/live.json" with { type: "json" };
import n8nLive from "./fixtures/n8n/live.json" with { type: "json" };
import vercelLive from "./fixtures/vercel/live.json" with { type: "json" };
import whatsappLive from "./fixtures/whatsapp/live.json" with { type: "json" };
import emailLive from "./fixtures/email/live.json" with { type: "json" };

// The factory (spec standard 1). Real when the credential is present (env or Vault, credentials.ts); in production a missing credential means
// "not_configured": the probe writes nothing, so a mock can never fake a heartbeat (D-049). Mock, from the recorded
// fixtures, only when ONE_CLIENT_MODE=mock (tests, previews against staging). The chosen mode per client is reported
// with every tick and shown on the Setup page.

const meta = z.object({ recorded: z.boolean() });
export const fixtures = {
  appHealth: z.object({ meta, data: z.record(z.string(), appHealthFixture) }).parse(appHealthLive),
  vercel: z.object({ meta, data: z.record(z.string(), vercelDeploymentsFixture) }).parse(vercelLive),
  chatwoot: z
    .object({
      meta,
      data: z.object({
        inboxes: chatwootInboxesFixture,
        summary: chatwootSummaryFixture,
        labels: z.record(z.string(), chatwootLabelsFixture),
      }),
    })
    .parse(chatwootLive),
  n8n: z
    .object({
      meta,
      data: z.object({
        workflows: z.record(z.string(), n8nWorkflowFixture),
        executions: z.record(z.string(), n8nExecutionsFixture),
      }),
    })
    .parse(n8nLive),
  whatsapp: z.object({ meta, data: whatsappPhoneFixture }).parse(whatsappLive),
  email: z.object({ meta, data: emailSentFixture }).parse(emailLive),
};

export function mockClients(): Clients {
  return {
    appHealth: { mode: "mock", client: new MockAppHealthClient(fixtures.appHealth.data) },
    vercel: { mode: "mock", client: new MockVercelClient(fixtures.vercel.data) },
    chatwoot: { mode: "mock", client: new MockChatwootClient(fixtures.chatwoot.data) },
    n8n: { mode: "mock", client: new MockN8nClient(fixtures.n8n.data) },
    whatsapp: { mode: "mock", client: new MockWhatsAppClient(fixtures.whatsapp.data) },
    email: { mode: "mock", client: new MockEmailClient(fixtures.email.data) },
  };
}

export function clientsFor(settings: Settings, credentials: Credentials): Clients {
  if (process.env.ONE_CLIENT_MODE === "mock") return mockClients();
  const {
    vercel: vercelToken,
    chatwoot: chatwootToken,
    n8n: n8nKey,
    whatsapp: whatsappToken,
    email: emailKey,
  } = credentials;
  return {
    appHealth: { mode: "real", client: new RealAppHealthClient() },
    vercel: vercelToken
      ? { mode: "real", client: new RealVercelClient(settings.vendors.vercel_api, vercelToken) }
      : { mode: "not_configured", client: null },
    chatwoot: chatwootToken
      ? { mode: "real", client: new RealChatwootClient(settings.hosts.chatwoot, chatwootToken) }
      : { mode: "not_configured", client: null },
    n8n: n8nKey
      ? { mode: "real", client: new RealN8nClient(secretEnv("ONE_N8N_BASE_URL") ?? settings.hosts.n8n, n8nKey) }
      : { mode: "not_configured", client: null },
    whatsapp: whatsappToken
      ? { mode: "real", client: new RealWhatsAppClient(settings.vendors.graph_api, whatsappToken) }
      : { mode: "not_configured", client: null },
    email: emailKey
      ? { mode: "real", client: new RealEmailClient(settings.vendors.resend_api, emailKey) }
      : { mode: "not_configured", client: null },
  };
}
