import { z } from "zod";

/** Partner push (spec B7.5, B8.1): labels, the credentials form and types shared by the partner and routing screens. */

export const AUTH_TYPES = ["bearer", "header", "basic", "none"] as const;
export const AUTH_LABEL: Record<(typeof AUTH_TYPES)[number], string> = {
  bearer: "Bearer token (Authorization: Bearer …)",
  header: "API key in a header of the partner's choice",
  basic: "HTTP Basic (user:password)",
  none: "No authentication (signed pushes only)",
};

export const PUSH_OUTCOME_LABEL: Record<string, string> = {
  created: "Created",
  duplicate: "Duplicate",
  rejected: "Rejected",
  error: "Error",
  timeout: "No answer",
};

export const EVENT_STATUS_LABEL: Record<string, string> = {
  received: "Received",
  applied: "Applied",
  ignored: "Ignored",
  held_unmapped: "Kept for mapping",
  error: "Error",
};

export const CredentialsSchema = z.object({
  type: z.enum(AUTH_TYPES),
  header: z.string().trim().max(60).regex(/^[A-Za-z0-9-]*$/, "Letters, digits and dashes only"),
  token: z.string().max(4000),
}).superRefine((v, ctx) => {
  if (v.type === "header" && !v.header) ctx.addIssue({ code: "custom", path: ["header"], message: "Give the header name" });
  if (v.type === "basic" && v.token && !v.token.includes(":")) ctx.addIssue({ code: "custom", path: ["token"], message: "Use user:password" });
});

export type PushRequest = {
  id: number; allocation_id: number; reference: string; attempt: number; url: string; sandbox: boolean; status_code: number | null;
  outcome: string | null; error: string | null; sent_at: string; completed_at: string | null;
};
export type PartnerEventRow = { id: number; partner_id: number; event_type: string; reference: string | null; status: string; result: string | null; received_at: string };
export type Dispute = {
  id: number; lead_id: number; lead_name: string | null; reference: string; partner_name: string; existing_record_id: string | null;
  existing_created_at: string | null; created_at: string;
};
export type PushOverview = {
  by_status: Record<string, number>;
  retrying: { id: number; reference: string; lead_id: number; partner_id: number; partner_name: string; attempts: number; next_push_at: string | null; last_error: string | null }[];
  requests: PushRequest[];
  events: PartnerEventRow[];
  disputes: Dispute[];
  duplicate_rate_7d: number | null;
};
export type PartnerConnection = {
  adapter_type: string; api_base_url: string | null; test_endpoint: string | null; auth_type: (typeof AUTH_TYPES)[number] | null; auth_header: string | null;
  has_token: boolean; has_inbound_secret: boolean; events_url_path: string; test_accepted: boolean; push: PushOverview;
};
