"use client";
// Staff override on a lead (attribution.review): credit this creator by hand, or reject this attribution. A reason is
// required and recorded.
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { overrideAttribution } from "@/lib/actions/links";

export function OverrideForm({
  studentLeadId,
  creatorId,
  canCredit,
  canReject,
}: {
  studentLeadId: number;
  creatorId: string;
  canCredit: boolean;
  canReject: boolean;
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [reason, setReason] = useState("");
  const send = (status: "manually_credited" | "manually_rejected") =>
    run(
      () => overrideAttribution({ studentLeadId, creatorId, status, reason }),
      () => (setReason(""), router.refresh()),
    );
  return (
    <div className="flex flex-col gap-2 rounded-xl ring-1 ring-line p-3">
      <p className="text-sm font-medium">{t("leads.override.title")}</p>
      <Field id="ov-reason" label={t("leads.override.reason")}>
        <Input
          id="ov-reason"
          maxLength={1000}
          value={reason}
          onChange={(e) => setReason(e.target.value)}
        />
      </Field>
      <div className="flex flex-wrap gap-2">
        {canCredit ? (
          <Button
            size="sm"
            disabled={pending || reason.trim().length < 3}
            onClick={() => send("manually_credited")}
          >
            {t("leads.override.credit")}
          </Button>
        ) : null}
        {canReject ? (
          <Button
            size="sm"
            variant="danger"
            disabled={pending || reason.trim().length < 3}
            onClick={() => send("manually_rejected")}
          >
            {t("leads.override.reject")}
          </Button>
        ) : null}
      </div>
    </div>
  );
}
