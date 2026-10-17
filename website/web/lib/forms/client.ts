/**
 * Application/enquiry form transport (spec 9.1A). The UI talks only to this interface: `serverApplicationClient`
 * (lib/forms/server-client.ts) calls the server actions; the mock (no network, nothing stored) remains for the
 * styleguide and unit tests.
 */
export interface FormContext {
  kind: "offering" | "group" | "university" | "compare" | "advisor" | "contact";
  offeringId?: number;
  groupKey?: string;
  universitySlug?: string;
  programmeLabel?: string;
  creatorHandle?: string;
}

export interface ContactPayload {
  name: string;
  phone: string; // E.164
  email: string;
  consentVersion: string;
  marketing: boolean;
  turnstileToken?: string;
  /** honeypot (hidden field) */
  website?: string;
  idempotencyKey: string;
}

export type StartResult =
  | { status: "code_sent"; attemptId: string; resendInSeconds: number; maskedEmail: string }
  | { status: "verified"; attemptId: string; reference?: string } // signed-in student: no code needed
  | { status: "error"; message: string };

export type VerifyResult =
  | { status: "verified"; reference?: string }
  | { status: "wrong_code"; attemptsLeft: number }
  | { status: "expired" | "too_many_attempts" | "error"; message: string };

export interface ApplicationClient {
  start(context: FormContext, contact: ContactPayload): Promise<StartResult>;
  resend(attemptId: string): Promise<StartResult>;
  verify(attemptId: string, code: string): Promise<VerifyResult>;
  saveStep(attemptId: string, step: number, data: Record<string, unknown>): Promise<{ ok: true } | { ok: false; message: string }>;
  submit(attemptId: string, data: Record<string, unknown>): Promise<{ ok: true; reference: string } | { ok: false; message: string }>;
}

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
const mask = (email: string) => email.replace(/^(.)(.*)(@.*)$/, (_, a: string, b: string, c: string) => `${a}${"•".repeat(Math.min(6, b.length))}${c}`);
const refFor = (seed: string) => `EDW-26-${Math.abs([...seed].reduce((h, ch) => (h * 31 + ch.charCodeAt(0)) | 0, 7)).toString(36).toUpperCase().padStart(5, "0").slice(0, 5)}`;

/** Demo transport: accepts any 6-digit code except 000000 (to exercise the wrong-code path). Stores nothing. */
export const mockApplicationClient: ApplicationClient = {
  async start(_ctx, contact) {
    await wait(400);
    return { status: "code_sent", attemptId: contact.idempotencyKey, resendInSeconds: 30, maskedEmail: mask(contact.email) };
  },
  async resend(attemptId) {
    await wait(300);
    return { status: "code_sent", attemptId, resendInSeconds: 30, maskedEmail: "your email" };
  },
  async verify(attemptId, code) {
    await wait(400);
    if (code === "000000") return { status: "wrong_code", attemptsLeft: 4 };
    return { status: "verified", reference: refFor(attemptId) };
  },
  async saveStep() {
    await wait(150);
    return { ok: true as const };
  },
  async submit(attemptId) {
    await wait(500);
    return { ok: true, reference: refFor(attemptId) };
  },
};
