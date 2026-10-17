import "server-only";
import { createHash } from "node:crypto";
import { z } from "zod";
import { publicEnv } from "@/lib/env-public";
import { PermanentJobError } from "@/lib/jobs/types";
import { log } from "@/lib/log";
import { emailProvider } from "@/lib/notify/email";
import { contractSignedEmail } from "@/lib/notify/templates";
import { adminClient } from "@/lib/supabase/admin";
import { contractContent } from "./data";
import { renderContractPdf, type CertificateSignature } from "./pdf";

export const CONTRACTS_BUCKET = "inf-contracts";
const SIGNED = ["active", "completed", "terminated", "superseded", "expired"];

const signatureRow = z.object({
  signer_user_id: z.uuid(),
  signer_name: z.string(),
  signer_role: z.string(),
  signer_designation: z.string().nullable(),
  signed_at: z.string(),
  signed_at_ist: z.string(),
  otp_channel: z.string(),
  otp_reference: z.string().nullable(),
  consent_version: z.number(),
  ip: z.string().nullable(),
  user_agent: z.string().nullable(),
  document_sha256: z.string(),
});

export const sha256Hex = (b: Uint8Array) => createHash("sha256").update(b).digest("hex");

/**
 * Builds the signed PDF for a countersigned contract (the exact signed version plus a signature certificate), stores
 * it write-once in the private bucket, records its hash, and emails a copy to every party. Idempotent: a version with
 * a recorded file is left alone. Runs as the service role (job contract.finalize, also called right after the
 * countersignature). Refuses when the stored document no longer matches its hash.
 */
export async function finalizeContract(
  contractId: string,
): Promise<"done" | "already" | "not_signed"> {
  const db = adminClient();
  const { data: c, error } = await db
    .from("contracts")
    .select("id, number, status, current_version_id, deal_id")
    .eq("id", contractId)
    .maybeSingle();
  if (error) throw new Error(error.message);
  if (!c?.current_version_id || !SIGNED.includes(c.status)) return "not_signed";
  const versionId = c.current_version_id;
  const existing = await db
    .from("contract_files")
    .select("id")
    .eq("version_id", versionId)
    .maybeSingle();
  if (existing.data) return "already";

  const check = await db.rpc("contract_integrity", { p_contract: c.id });
  const ok = z.object({ ok: z.boolean() }).safeParse(check.data);
  if (check.error || !ok.success || !ok.data.ok)
    throw new PermanentJobError("integrity check failed; not finalizing");

  const [{ data: v, error: e1 }, { data: sigs, error: e2 }] = await Promise.all([
    db.from("contract_versions").select("version, content, sha256").eq("id", versionId).single(),
    db
      .from("signatures")
      .select(
        "signer_user_id, signer_name, signer_role, signer_designation, signed_at, signed_at_ist, otp_channel, otp_reference, consent_version, ip, user_agent, document_sha256",
      )
      .eq("version_id", versionId)
      .order("signed_at"),
  ]);
  if (e1 || e2) throw new Error(e1?.message ?? e2?.message);
  const signatures = z.array(signatureRow).parse(sigs);
  const pdf = await renderContractPdf(contractContent.parse(v.content), {
    number: c.number,
    version: v.version,
    sha256: v.sha256,
    generatedAt: new Date().toISOString().replace("T", " ").slice(0, 19),
    signatures,
  });

  const path = `${c.id}/${c.number}-v${String(v.version)}.pdf`;
  let stored: Uint8Array = pdf;
  const up = await db.storage
    .from(CONTRACTS_BUCKET)
    .upload(path, pdf, { contentType: "application/pdf", upsert: false });
  if (up.error) {
    // A previous attempt stored the file but didn't record it: record what is stored (write-once, never replaced).
    if (!/exist|duplicate/i.test(up.error.message))
      throw new Error(`upload failed: ${up.error.message}`);
    const dl = await db.storage.from(CONTRACTS_BUCKET).download(path);
    if (dl.error) throw new Error(`download failed: ${dl.error.message}`);
    stored = new Uint8Array(await dl.data.arrayBuffer());
  }
  const rec = await db.rpc("contract_file_record", {
    p_contract: c.id,
    p_version: versionId,
    p_path: path,
    p_sha256: sha256Hex(stored),
  });
  if (rec.error) throw new Error(rec.error.message);

  await emailCopies(c.id, c.number, c.deal_id, signatures, stored);
  return "done";
}

async function emailCopies(
  contractId: string,
  number: string,
  dealId: string,
  signatures: (CertificateSignature & { signer_user_id: string })[],
  pdf: Uint8Array,
): Promise<void> {
  const db = adminClient();
  const deal = await db.from("deals").select("creator_id, owner_id").eq("id", dealId).single();
  const [creator, owner] = await Promise.all([
    db
      .from("creators")
      .select("display_name, email")
      .eq("id", deal.data?.creator_id ?? "")
      .maybeSingle(),
    deal.data?.owner_id
      ? db
          .from("staff_profiles")
          .select("full_name, email")
          .eq("user_id", deal.data.owner_id)
          .maybeSingle()
      : Promise.resolve({ data: null }),
  ]);
  const to = new Map<string, { name: string; link: string }>();
  const add = (email: string | null | undefined, name: string, link: string) => {
    if (email && !to.has(email.toLowerCase())) to.set(email.toLowerCase(), { name, link });
  };
  const site = publicEnv.siteUrl;
  add(
    creator.data?.email,
    creator.data?.display_name ?? "",
    `${site}/creator/contracts/${contractId}`,
  );
  for (const s of signatures) {
    const u = await db.auth.admin.getUserById(s.signer_user_id);
    const path =
      s.signer_role === "signatory" ? "admin" : s.signer_role === "agency" ? "agency" : "creator";
    add(u.data.user?.email, s.signer_name, `${site}/${path}/contracts/${contractId}`);
  }
  add(owner.data?.email, owner.data?.full_name ?? "", `${site}/admin/contracts/${contractId}`);
  const attachment = {
    filename: `${number}.pdf`,
    contentType: "application/pdf",
    content: Buffer.from(pdf),
  };
  for (const [email, r] of to) {
    try {
      await emailProvider().send({
        ...contractSignedEmail(r.name, number, r.link),
        to: email,
        attachments: [attachment],
        idempotencyKey: `contract_signed:${contractId}:${email}`,
      });
    } catch (e) {
      // The PDF is stored and every party can download it from the portal; a failed copy is logged, not retried.
      log.warn("contracts.copy_failed", {
        contract_id: contractId,
        error: e instanceof Error ? e.message : String(e),
      });
    }
  }
}
