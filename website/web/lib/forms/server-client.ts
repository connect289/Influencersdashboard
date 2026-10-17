import { resendCodeAction, saveStepAction, startFormAction, submitFormAction, verifyCodeAction } from "@/app/actions/forms";
import type { ApplicationClient, FormContext, StartResult } from "./client";

/** The real form transport: server actions (email code, lead_intake, outbox side effects). */
const surfaceFor = (k: FormContext["kind"]) => (k === "contact" ? "enquiry" : k === "advisor" ? "gate" : "application");

function toStart(r: Awaited<ReturnType<typeof startFormAction>>): StartResult {
  if (r.status === "code_sent") return { status: "code_sent", attemptId: r.attemptId, resendInSeconds: r.resendIn, maskedEmail: r.maskedEmail };
  if (r.status === "verified") return { status: "verified", attemptId: r.attemptId, reference: r.reference };
  return { status: "error", message: r.message };
}

export const serverApplicationClient: ApplicationClient = {
  async start(ctx, c) {
    return toStart(
      await startFormAction({
        surface: surfaceFor(ctx.kind),
        context: {
          offering_id: ctx.offeringId,
          group_key: ctx.groupKey,
          university_slug: ctx.universitySlug,
          programme_label: ctx.programmeLabel,
          creator_handle: ctx.creatorHandle,
        },
        name: c.name,
        phone: c.phone,
        email: c.email,
        consentVersion: c.consentVersion,
        marketing: c.marketing,
        turnstileToken: c.turnstileToken,
        website: c.website,
        idempotencyKey: c.idempotencyKey,
      }),
    );
  },
  async resend(attemptId) {
    return toStart(await resendCodeAction(attemptId));
  },
  async verify(attemptId, code) {
    const r = await verifyCodeAction(attemptId, code);
    if (r.status === "verified") return { status: "verified", reference: r.reference };
    if (r.status === "wrong_code") return r;
    return { status: r.status, message: r.message };
  },
  saveStep: (attemptId, step, data) => saveStepAction(attemptId, step, data),
  submit: (attemptId, data) => submitFormAction(attemptId, data),
};
