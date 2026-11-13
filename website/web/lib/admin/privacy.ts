import { z } from "zod";

/**
 * Privacy requests in the admin (web17, D-096): input validation for the three actions, the shape of a request as the
 * database returns it, and the wording of the checklist and of every refusal. Pure, so it is tested without a database.
 * The database enforces every rule again (web_admin_privacy_*).
 */

const id = z.coerce.number().int().positive().max(Number.MAX_SAFE_INTEGER);
const note = z
  .string()
  .trim()
  .max(300, "Keep the note under 300 characters.")
  .refine((v) => v.length >= 3, "Add a short note: what was done, and the CRM reference.");

/** "Erase" or "copy sent": the admin must tick the confirmation. */
export const fulfilInput = z.object({
  id,
  kind: z.enum(["delete", "export"]),
  confirm: z.literal("on", "Tick the confirmation first."),
});

/** One CRM ticked on the checklist. */
export const systemInput = z.object({
  id,
  system: z.enum(["spark", "b2b"]),
  state: z.enum(["done", "not_applicable"]),
  note,
});

/** Mark done / reject (opt-out requests, and rejecting the others). The note is optional here; the database asks for it where it must. */
export const closeInput = z.object({
  id,
  status: z.enum(["done", "rejected"]),
  note: z.string().trim().max(500, "Keep the note under 500 characters."),
});

export const requestId = id;

export type SystemKey = "website" | "spark" | "b2b";
export type SystemState = "pending" | "done" | "not_applicable";

export interface SystemEntry {
  state?: SystemState;
  at?: string;
  by?: string;
  note?: string;
  did?: "erased" | "copy_sent";
  downloaded_at?: string;
  downloaded_by?: string;
  counts?: Counts;
}

export type Counts = Partial<
  Record<
    | "enquiries"
    | "applications"
    | "chats"
    | "chat_messages"
    | "saved_programmes"
    | "comparisons"
    | "callbacks"
    | "consents"
    | "sessions"
    | "unverified_forms"
    | "queued_jobs",
    number
  >
>;

export interface LeadRef {
  lead_id: number;
  tie: string | null;
}

export interface PrivacyRequest {
  id: number;
  email_norm: string;
  kind: "delete" | "opt_out" | "export";
  status: "open" | "done" | "rejected";
  requested_at: string;
  processed_at: string | null;
  processed_by: string | null;
  note: string | null;
  systems: Partial<Record<SystemKey, SystemEntry>> | null;
  leads: LeadRef[] | null;
  /** Only on an open delete / export request whose website step has not run. */
  preview?: { requester_problem: string | null; counts: Counts; leads: LeadRef[]; other_open: number[] };
}

export const KIND_LABEL: Record<PrivacyRequest["kind"], string> = {
  delete: "Delete my data",
  export: "Copy of my data",
  opt_out: "Opt out of contact",
};

export const SYSTEM_LABEL: Record<SystemKey, string> = {
  website: "Website",
  spark: "Spark (B2C CRM)",
  b2b: "B2B CRM (shared lead)",
};

export const STATE_LABEL: Record<SystemState, string> = {
  pending: "pending",
  done: "done",
  not_applicable: "not applicable",
};

/** Whether the website step of a delete / export request has run (after it the request can no longer be rejected). */
export function websiteDone(r: Pick<PrivacyRequest, "systems">): boolean {
  return r.systems?.website?.state === "done";
}

/** The checklist rows of a request, in a fixed order; empty before the website step. */
export function checklist(r: Pick<PrivacyRequest, "systems">): { key: SystemKey; entry: SystemEntry }[] {
  if (!websiteDone(r)) return [];
  return (["website", "spark", "b2b"] as const).map((key) => ({ key, entry: r.systems?.[key] ?? {} }));
}

const COUNT_WORDS: [keyof Counts, string, string][] = [
  ["enquiries", "verified form", "verified forms"],
  ["applications", "application or enquiry", "applications and enquiries"],
  ["chats", "Witty chat", "Witty chats"],
  ["chat_messages", "chat message", "chat messages"],
  ["saved_programmes", "saved programme", "saved programmes"],
  ["comparisons", "saved comparison", "saved comparisons"],
  ["callbacks", "callback request", "callback requests"],
  ["sessions", "sign-in session", "sign-in sessions"],
];

/** "2 verified forms, 1 application or enquiry, …": what the website holds, without the zero lines. */
export function countsSummary(c: Counts | undefined | null): string {
  const parts = COUNT_WORDS.flatMap(([k, one, many]) => {
    const n = c?.[k] ?? 0;
    return n > 0 ? [`${n.toLocaleString("en-IN")} ${n === 1 ? one : many}`] : [];
  });
  return parts.length ? parts.join(", ") : "no saved items, forms or chats";
}

const TIE_TEXT: Record<string, string> = {
  email_not_verified: "the account's email is not verified",
  other_confirmed_email: "the lead has another confirmed email",
  enrolled: "the lead is an enrolled student",
  crm_owned: "a counsellor or partner is working the lead",
  recorded_only:
    "the website wrote to it earlier, but the account's number no longer leads to it (merged, deleted or already erased)",
};

/** One line per shared lead: the account's own lead, or why the CRM admin should confirm first. */
export function leadLine(l: LeadRef): string {
  return l.tie === null
    ? `Lead #${l.lead_id}: this account's own lead.`
    : `Lead #${l.lead_id}: confirm in the CRM before acting (${Object.hasOwn(TIE_TEXT, l.tie) ? TIE_TEXT[l.tie] : l.tie.replace(/_/g, " ")}).`;
}

const ERRORS: Record<string, string> = {
  forbidden: "Only a super admin can do this.",
  not_found: "This request no longer exists.",
  wrong_kind: "This kind of request is not fulfilled this way.",
  rejected: "This request was rejected.",
  not_open: "This request is already closed.",
  no_verified_requester:
    "This request is not tied to a signed-in account, so the requester is not verified. Reject it with a note.",
  account_erased: "This account has already been erased. Reject the request with a note.",
  requester_mismatch:
    "The account's email is no longer the one that filed this request, so the requester is not verified. Reject it with a note and ask for a new request.",
  other_requests_open:
    "This account has another open request. Complete or reject it first: an opt-out needs the phone number and a copy needs the data, and the erasure removes both.",
  not_downloaded: "Download the copy and send it to the requester first.",
  website_first: "Do the website step first.",
  bad_system: "Unknown system.",
  bad_state: "Unknown state.",
  bad_status: "Unknown status.",
  note_required: "Add a short note (at least 3 characters).",
  already_set: "This system is already ticked.",
  lead_not_erased:
    "The account's own lead is not anonymised in the shared lead table yet. Erase it in the B2B CRM first (the lead's erase action, or the erasure request Spark raised there), then tick this.",
  use_fulfil: "A delete or copy request is completed with the steps above, not marked done by hand.",
  fulfil_started: "The website step has already run, so this request can no longer be rejected.",
};

/** A sentence for a refusal code from the database (never the raw code alone). */
export function privacyError(code: string | undefined | null): string {
  return code && Object.hasOwn(ERRORS, code) ? ERRORS[code]! : "That did not work. Reload the page and try again.";
}

/** File name of the downloaded copy: the request id only, never the address. */
export function exportFileName(requestIdValue: number): string {
  return `eduwit-data-copy-request-${requestIdValue}.json`;
}
