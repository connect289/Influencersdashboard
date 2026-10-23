// The vendor interfaces (spec standard 1). Each has a Real implementation built from runtime config and a Mock driven
// by recorded fixtures; lib/clients/index.ts picks one and says which. Nothing outside lib/clients calls a vendor.

export type ClientMode = "real" | "mock" | "not_configured";

export interface AppHealthClient {
  /**
   * GET the app's health path. For a JSON health endpoint ("json_ok"), ok means a 2xx whose body says ok: true or
   * status: "ok"; for an
   * app without one ("reachable", for example Spark's "/"), ok means any 2xx answer.
   */
  health(url: string, expect: "json_ok" | "reachable"): Promise<{ ok: boolean; status: number; ms: number }>;
}

export type VercelDeployment = { uid: string; state: string; createdAt: number; url: string | null };

export interface VercelClient {
  latestProduction(project: string, team: string): Promise<VercelDeployment | null>;
}

export interface ChatwootClient {
  inboxCount(accountId: string): Promise<number>;
  incomingMessages(accountId: string, sinceUnix: number, untilUnix: number): Promise<number>;
  conversationLabels(accountId: string, conversationId: number): Promise<string[]>;
}

export type N8nExecution = { id: string; status: string; startedAt: string | null; stoppedAt: string | null };

export interface N8nClient {
  workflow(id: string): Promise<{ id: string; active: boolean; name: string }>;
  executions(workflowId: string, limit: number): Promise<N8nExecution[]>;
}

export interface WhatsAppClient {
  phoneNumber(phoneNumberId: string): Promise<{ quality_rating: string | null; status: string | null }>;
}

import type { EmailClient } from "./email.ts";

export type Clients = {
  appHealth: { mode: ClientMode; client: AppHealthClient };
  vercel: { mode: ClientMode; client: VercelClient | null };
  chatwoot: { mode: ClientMode; client: ChatwootClient | null };
  n8n: { mode: ClientMode; client: N8nClient | null };
  whatsapp: { mode: ClientMode; client: WhatsAppClient | null };
  email: { mode: ClientMode; client: EmailClient | null };
};
