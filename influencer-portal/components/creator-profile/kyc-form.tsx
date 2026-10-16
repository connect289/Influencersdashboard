"use client";
import { FileCheck2, Lock, Upload } from "lucide-react";
import { useTranslations } from "next-intl";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { Input, Select } from "@/components/ui/input";
import { Banner } from "@/components/ui/states";
import { StatusBadge } from "@/components/ui/badge";
import { useAction } from "@/components/ui/use-action";
import { kycProofUploadUrl, saveKyc } from "@/lib/actions/creator-profile";
import { GST_STATUSES, KYC_PROOF_MAX_BYTES, KYC_PROOF_TYPES } from "@/lib/creators/schemas";
import { formatDate } from "@/lib/format";
import { createClient } from "@/lib/supabase/browser";
import type { KycView } from "./types";

type GstStatus = (typeof GST_STATUSES)[number];

/**
 * KYC details. The stored PAN and account number are never sent to the browser: the form shows them masked and leaves
 * the inputs blank; typing a new value replaces the stored one.
 */
export function KycForm({ creatorId, kyc, canEdit }: { creatorId: string; kyc: KycView; canEdit: boolean }) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const [uploading, setUploading] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);
  const [v, setV] = useState({
    pan: "",
    nameOnPan: kyc.name_on_pan ?? "",
    gstStatus: (kyc.gst_status ?? "unregistered"),
    gstin: kyc.gstin ?? "",
    bankAccount: "",
    ifsc: kyc.ifsc ?? "",
    accountHolder: kyc.account_holder ?? "",
    proofPath: "",
    proofName: "",
  });
  const set = <K extends keyof typeof v>(k: K, value: (typeof v)[K]) => setV((x) => ({ ...x, [k]: value }));

  async function upload(file: File) {
    if (!(KYC_PROOF_TYPES as readonly string[]).includes(file.type) || file.size > KYC_PROOF_MAX_BYTES) {
      toast.error(t("kyc.errors.proofType"));
      return;
    }
    setUploading(true);
    try {
      const signed = await kycProofUploadUrl({
        creatorId,
        fileName: file.name,
        type: file.type as (typeof KYC_PROOF_TYPES)[number],
        size: file.size,
      });
      if (!signed.ok || !signed.data) {
        toast.error(signed.ok ? t("errors.generic") : signed.error);
        return;
      }
      const { error } = await createClient()
        .storage.from("inf-kyc")
        .uploadToSignedUrl(signed.data.path, signed.data.token, file, { contentType: file.type });
      if (error) toast.error(t("kyc.errors.uploadFailed"));
      else setV((x) => ({ ...x, proofPath: signed.data?.path ?? "", proofName: file.name }));
    } finally {
      setUploading(false);
    }
  }

  const missingSecrets = !kyc.pan_masked && v.pan === "";
  const missingAccount = !kyc.bank_masked && v.bankAccount === "";
  return (
    <Card>
      <CardHeader
        title={t("kyc.title")}
        description={t("kyc.hint")}
        actions={<StatusBadge status={kyc.status} label={t(`kyc.status.${kyc.status}`)} />}
      />
      <div className="mb-4 flex flex-col gap-2">
        {kyc.status === "rejected" && kyc.rejection_reason ? (
          <Banner tone="danger">{t("kyc.rejectedBanner", { reason: kyc.rejection_reason })}</Banner>
        ) : null}
        {kyc.status === "verified" ? (
          <Banner tone="success">
            {t("kyc.verifiedBanner", { date: kyc.verified_at ? formatDate(kyc.verified_at) : "" })}
          </Banner>
        ) : null}
        {kyc.status === "submitted" ? <Banner>{t("kyc.submittedBanner")}</Banner> : null}
        <p className="flex items-center gap-2 text-xs text-muted">
          <Lock className="size-3.5" aria-hidden /> {t("kyc.encryptedNote")}
        </p>
      </div>
      <form
        className="grid gap-4 md:grid-cols-2"
        onSubmit={(e) => {
          e.preventDefault();
          run(
            () => saveKyc(creatorId, v),
            () => setV((x) => ({ ...x, pan: "", bankAccount: "", proofPath: "", proofName: "" })),
          );
        }}
      >
        <Field
          id="k-pan"
          label={t("kyc.fields.pan")}
          hint={kyc.pan_masked ? t("kyc.fields.onFile", { value: kyc.pan_masked }) : t("kyc.fields.panHint")}
          required={!kyc.pan_masked}
        >
          <Input
            id="k-pan"
            value={v.pan}
            onChange={(e) => set("pan", e.target.value.toUpperCase())}
            autoComplete="off"
            autoCapitalize="characters"
            spellCheck={false}
            maxLength={12}
            placeholder={kyc.pan_masked ?? "ABCDE1234F"}
            disabled={!canEdit}
          />
        </Field>
        <Field id="k-name" label={t("kyc.fields.nameOnPan")} required>
          <Input
            id="k-name"
            value={v.nameOnPan}
            onChange={(e) => set("nameOnPan", e.target.value)}
            required
            maxLength={120}
            disabled={!canEdit}
          />
        </Field>
        <Field id="k-gst" label={t("kyc.fields.gstStatus")} hint={t("kyc.fields.gstHint")}>
          <Select
            id="k-gst"
            value={v.gstStatus}
            onChange={(e) => set("gstStatus", e.target.value as GstStatus)}
            disabled={!canEdit}
          >
            {GST_STATUSES.map((s) => (
              <option key={s} value={s}>
                {t(`kyc.gst.${s}`)}
              </option>
            ))}
          </Select>
        </Field>
        {v.gstStatus !== "unregistered" ? (
          <Field id="k-gstin" label={t("kyc.fields.gstin")} required>
            <Input
              id="k-gstin"
              value={v.gstin}
              onChange={(e) => set("gstin", e.target.value.toUpperCase())}
              autoCapitalize="characters"
              spellCheck={false}
              maxLength={15}
              required
              disabled={!canEdit}
            />
          </Field>
        ) : (
          <div className="hidden md:block" />
        )}
        <Field
          id="k-acct"
          label={t("kyc.fields.account")}
          hint={kyc.bank_masked ? t("kyc.fields.onFile", { value: kyc.bank_masked }) : undefined}
          required={!kyc.bank_masked}
        >
          <Input
            id="k-acct"
            value={v.bankAccount}
            onChange={(e) => set("bankAccount", e.target.value)}
            inputMode="numeric"
            autoComplete="off"
            maxLength={22}
            placeholder={kyc.bank_masked ?? ""}
            disabled={!canEdit}
          />
        </Field>
        <Field id="k-ifsc" label={t("kyc.fields.ifsc")} required>
          <Input
            id="k-ifsc"
            value={v.ifsc}
            onChange={(e) => set("ifsc", e.target.value.toUpperCase())}
            autoCapitalize="characters"
            spellCheck={false}
            maxLength={11}
            required
            disabled={!canEdit}
          />
        </Field>
        <Field id="k-holder" label={t("kyc.fields.accountHolder")} required>
          <Input
            id="k-holder"
            value={v.accountHolder}
            onChange={(e) => set("accountHolder", e.target.value)}
            required
            maxLength={120}
            disabled={!canEdit}
          />
        </Field>
        <div className="flex flex-col gap-1.5">
          <span className="text-sm font-medium">{t("kyc.fields.proof")}</span>
          <input
            ref={fileRef}
            type="file"
            accept={KYC_PROOF_TYPES.join(",")}
            className="sr-only"
            tabIndex={-1}
            aria-hidden
            onChange={(e) => {
              const f = e.target.files?.[0];
              if (f) void upload(f);
              e.target.value = "";
            }}
          />
          <Button
            type="button"
            variant="secondary"
            disabled={!canEdit || uploading}
            onClick={() => fileRef.current?.click()}
          >
            {v.proofPath || kyc.has_proof ? <FileCheck2 /> : <Upload />}
            {uploading
              ? t("kyc.uploading")
              : v.proofName
                ? v.proofName
                : kyc.has_proof
                  ? t("kyc.replaceProof")
                  : t("kyc.uploadProof")}
          </Button>
          <p className="text-xs text-muted">{t("kyc.fields.proofHint")}</p>
        </div>
        {canEdit ? (
          <div className="md:col-span-2">
            <Button type="submit" disabled={pending || uploading || missingSecrets || missingAccount}>
              {kyc.status === "verified" ? t("kyc.saveChanges") : t("kyc.submit")}
            </Button>
            {kyc.status === "verified" ? <p className="mt-2 text-xs text-muted">{t("kyc.reverifyNote")}</p> : null}
          </div>
        ) : null}
      </form>
    </Card>
  );
}
