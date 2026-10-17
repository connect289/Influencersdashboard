"use client";
import { Eye, EyeOff } from "lucide-react";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { StatusBadge } from "@/components/ui/badge";
import { Banner } from "@/components/ui/states";
import { useAction } from "@/components/ui/use-action";
import { revealKyc, verifyKyc } from "@/lib/actions/creator-profile";
import { formatDateTime } from "@/lib/format";
import type { KycView } from "./types";

interface Revealed {
  pan: string | null;
  bankAccount: string | null;
  proofUrl: string | null;
}

/** Staff view of a creator's KYC: masked details; Finance can reveal (reason required, audited) and verify or reject. */
export function KycReview({
  creatorId,
  kyc,
  canReveal,
  canVerify,
}: {
  creatorId: string;
  kyc: KycView;
  canReveal: boolean;
  canVerify: boolean;
}) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const [revealed, setRevealed] = useState<Revealed | null>(null);
  const [gstinOk, setGstinOk] = useState(kyc.gstin_verified ?? false);
  const rows: [string, string | null | undefined][] = [
    [t("kyc.fields.pan"), revealed?.pan ?? kyc.pan_masked],
    [t("kyc.fields.nameOnPan"), kyc.name_on_pan],
    [t("kyc.fields.gstStatus"), kyc.gst_status ? t(`kyc.gst.${kyc.gst_status}`) : null],
    [t("kyc.fields.gstin"), kyc.gstin],
    [t("kyc.fields.account"), revealed?.bankAccount ?? kyc.bank_masked],
    [t("kyc.fields.ifsc"), kyc.ifsc],
    [t("kyc.fields.accountHolder"), kyc.account_holder],
  ];
  return (
    <Card>
      <CardHeader
        title={t("kyc.title")}
        description={
          kyc.submitted_at
            ? t("kyc.submittedOn", { date: formatDateTime(kyc.submitted_at) })
            : undefined
        }
        actions={<StatusBadge status={kyc.status} label={t(`kyc.status.${kyc.status}`)} />}
      />
      {!kyc.exists ? (
        <Banner>{t("kyc.notStarted")}</Banner>
      ) : (
        <>
          {kyc.status === "rejected" && kyc.rejection_reason ? (
            <Banner tone="danger">
              {t("kyc.rejectedBanner", { reason: kyc.rejection_reason })}
            </Banner>
          ) : null}
          <dl className="mt-2 grid grid-cols-1 gap-x-6 gap-y-2 text-sm sm:grid-cols-2">
            {rows.map(([label, value]) => (
              <div key={label} className="flex justify-between gap-3 border-b border-line py-1.5">
                <dt className="text-muted">{label}</dt>
                <dd className="font-medium tabular-nums">{value ?? "—"}</dd>
              </div>
            ))}
          </dl>
          <div className="mt-4 flex flex-wrap items-center gap-2">
            {canReveal && !revealed ? (
              <ConfirmDialog
                title={t("kyc.reveal.title")}
                description={t("kyc.reveal.body")}
                reasonLabel={t("kyc.reveal.reason")}
                actionLabel={t("kyc.reveal.action")}
                danger={false}
                pending={pending}
                onConfirm={(reason, close) =>
                  run(
                    () => revealKyc(creatorId, reason),
                    (data) => {
                      if (data) setRevealed(data);
                      close();
                    },
                  )
                }
                trigger={
                  <Button variant="secondary" size="sm">
                    <Eye /> {t("kyc.reveal.open")}
                  </Button>
                }
              />
            ) : null}
            {revealed ? (
              <>
                <Button variant="secondary" size="sm" onClick={() => setRevealed(null)}>
                  <EyeOff /> {t("kyc.reveal.hide")}
                </Button>
                {revealed.proofUrl ? (
                  <Button asChild variant="link" size="sm">
                    <a href={revealed.proofUrl} target="_blank" rel="noopener noreferrer">
                      {t("kyc.reveal.proof")}
                    </a>
                  </Button>
                ) : null}
              </>
            ) : null}
          </div>
          {canVerify && kyc.status !== "pending" ? (
            <div className="mt-4 flex flex-col gap-3 border-t border-line pt-4">
              {kyc.gstin ? (
                <label className="flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    className="size-4 accent-[var(--primary)]"
                    checked={gstinOk}
                    onChange={(e) => setGstinOk(e.target.checked)}
                  />
                  {t("kyc.gstinChecked")}
                </label>
              ) : null}
              <div className="flex flex-wrap gap-2">
                {kyc.status !== "verified" ? (
                  <Button
                    size="sm"
                    disabled={pending}
                    onClick={() =>
                      run(() =>
                        verifyKyc({ creatorId, approve: true, reason: "", gstinVerified: gstinOk }),
                      )
                    }
                  >
                    {t("kyc.verify")}
                  </Button>
                ) : null}
                {kyc.status !== "rejected" ? (
                  <ConfirmDialog
                    title={t("kyc.rejectTitle")}
                    description={t("kyc.rejectBody")}
                    reasonLabel={t("kyc.rejectReason")}
                    actionLabel={t("kyc.reject")}
                    pending={pending}
                    onConfirm={(reason, close) =>
                      run(
                        () =>
                          verifyKyc({ creatorId, approve: false, reason, gstinVerified: false }),
                        close,
                      )
                    }
                    trigger={
                      <Button size="sm" variant="secondary">
                        {t("kyc.reject")}
                      </Button>
                    }
                  />
                ) : null}
              </div>
            </div>
          ) : null}
        </>
      )}
    </Card>
  );
}
