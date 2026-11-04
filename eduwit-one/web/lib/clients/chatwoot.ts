import { z } from "zod";
import { fetchJson } from "../http.ts";
import type { ChatwootClient } from "./types.ts";

// Chatwoot application API, read only: inbox count (liveness), incoming message count over a window (WITTY-03 reads
// it through the chatwoot heartbeat), and one conversation's labels (WITTY-05). No contact or message content is read.

export const chatwootInboxesFixture = z.object({ payload: z.array(z.object({ id: z.number() })) });
export const chatwootSummaryFixture = z.object({ incoming_messages_count: z.number() });
export const chatwootLabelsFixture = z.object({ payload: z.array(z.string()) });

export type ChatwootFixtures = {
  inboxes: z.infer<typeof chatwootInboxesFixture>;
  summary: z.infer<typeof chatwootSummaryFixture>;
  labels: Record<string, z.infer<typeof chatwootLabelsFixture>>;
};

export class RealChatwootClient implements ChatwootClient {
  private readonly host: string;
  private readonly token: string;

  constructor(host: string, token: string) {
    this.host = host;
    this.token = token;
  }

  private get(path: string) {
    return fetchJson("chatwoot", `${this.host}${path}`, { headers: { api_access_token: this.token } }).then(
      (r) => r.json,
    );
  }

  async inboxes(accountId: string) {
    const body = chatwootInboxesFixture.parse(
      await this.get(`/api/v1/accounts/${encodeURIComponent(accountId)}/inboxes`),
    );
    return { payload: body.payload.map((i) => ({ id: i.id })) };
  }

  async summary(accountId: string, sinceUnix: number, untilUnix: number) {
    const q = new URLSearchParams({ type: "account", since: String(sinceUnix), until: String(untilUnix) });
    const body = chatwootSummaryFixture.parse(
      await this.get(`/api/v2/accounts/${encodeURIComponent(accountId)}/reports/summary?${q}`),
    );
    return { incoming_messages_count: body.incoming_messages_count };
  }

  async labels(accountId: string, conversationId: number) {
    return chatwootLabelsFixture.parse(
      await this.get(`/api/v1/accounts/${encodeURIComponent(accountId)}/conversations/${conversationId}/labels`),
    );
  }

  async inboxCount(accountId: string) {
    return (await this.inboxes(accountId)).payload.length;
  }

  async incomingMessages(accountId: string, sinceUnix: number, untilUnix: number) {
    return (await this.summary(accountId, sinceUnix, untilUnix)).incoming_messages_count;
  }

  async conversationLabels(accountId: string, conversationId: number) {
    return (await this.labels(accountId, conversationId)).payload;
  }
}

export class MockChatwootClient implements ChatwootClient {
  private readonly f: ChatwootFixtures;

  constructor(f: ChatwootFixtures) {
    this.f = f;
  }

  async inboxCount() {
    return this.f.inboxes.payload.length;
  }

  async incomingMessages() {
    return this.f.summary.incoming_messages_count;
  }

  async conversationLabels(_accountId: string, conversationId: number) {
    return (this.f.labels[String(conversationId)] ?? this.f.labels.default ?? { payload: [] }).payload;
  }
}
