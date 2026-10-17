import "server-only";
import { whatsappLink } from "@/content/site";
import { sendCapi } from "./capi";
import { email } from "./email";
import { privacyRequestEmail, submissionConfirmationEmail } from "./email/templates";
import { log } from "./log";
import { registerOutboxHandler } from "./outbox";
import { getSettings } from "./settings";

/**
 * Side-effect handlers for the transactional outbox (spec 3A): confirmation emails and Conversions API events. Each is
 * idempotent: email providers receive the job's dedupe key as their idempotency key; CAPI de-duplicates on event_id.
 */
type Attribution = { ad_consent?: boolean; click_ids?: Record<string, string>; landing_url?: string };

registerOutboxHandler("email_confirmation", async (job) => {
  const p = job.payload as { kind: string; reference?: string; email: string; name?: string; request?: string; context?: { programme_label?: string } };
  if (p.kind === "privacy_request") {
    await email().send(p.email, privacyRequestEmail({ name: p.name, request: p.request ?? "delete" }), { idempotencyKey: job.dedupe_key });
    return;
  }
  const settings = await getSettings();
  await email().send(
    p.email,
    submissionConfirmationEmail({
      kind: p.kind === "application" ? "application" : "enquiry",
      name: p.name,
      reference: p.reference ?? "",
      programme: p.context?.programme_label,
      whatsappHref: whatsappLink(settings.counsellor_whatsapp, `Hi Eduwit, my reference is ${p.reference}.`),
    }),
    { idempotencyKey: job.dedupe_key },
  );
});

async function capiJob(name: "Lead" | "SubmitApplication", payload: Record<string, unknown>) {
  const a = (payload.attribution ?? {}) as Attribution;
  // Ads measurement only with the visitor's marketing-cookie consent (D-047).
  if (a.ad_consent !== true) {
    log("info", "capi.skipped_no_consent", { event: name });
    return;
  }
  await sendCapi({
    name,
    eventId: String(payload.event_id),
    email: typeof payload.email === "string" ? payload.email : undefined,
    phone: typeof payload.phone === "string" ? payload.phone : undefined,
    fbp: a.click_ids?.fbp,
    fbc: a.click_ids?.fbc,
    sourcePath: a.landing_url,
  });
}

registerOutboxHandler("capi_lead", (job) => capiJob("Lead", job.payload));
registerOutboxHandler("capi_submit_application", (job) => capiJob("SubmitApplication", job.payload));
