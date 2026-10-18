"use client";
import { Download, Trash2 } from "lucide-react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { StatusBadge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { Field } from "@/components/ui/field";
import { Textarea } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { createPrivacyRequest } from "@/lib/actions/privacy";
import { formatDate, formatDateTime } from "@/lib/format";
import type { MyRequest } from "@/lib/privacy/data";

/**
 * The creator's privacy page (spec 16, DPDP): download a copy of their data, ask for their account to be deleted
 * (financial and contract records are kept as the law requires), and see their requests.
 */
export function PrivacyPanel({ requests }: { requests: MyRequest[] }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [reason, setReason] = useState("");
  const ready = requests.find((r) => r.kind === "export" && r.file_ready);
  const openDeletion = requests.find((r) => r.kind === "deletion" && r.status === "requested");
  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardHeader title={t("privacy.export.title")} description={t("privacy.export.hint")} />
        <div className="flex flex-wrap gap-2">
          {ready ? (
            <Button asChild size="sm">
              <a href={`/api/privacy/export/${ready.id}`}>
                <Download /> {t("privacy.export.download")}
              </a>
            </Button>
          ) : null}
          <Button
            size="sm"
            variant={ready ? "secondary" : "primary"}
            disabled={pending}
            onClick={() =>
              run(
                () => createPrivacyRequest({ kind: "export" }),
                () => router.refresh(),
              )
            }
          >
            {t("privacy.export.request")}
          </Button>
        </div>
        {ready?.file_expires_at ? (
          <p className="mt-2 text-xs text-muted">
            {t("privacy.export.expires", { date: formatDateTime(ready.file_expires_at) })}
          </p>
        ) : null}
      </Card>
      <Card>
        <CardHeader title={t("privacy.deletion.title")} description={t("privacy.deletion.hint")} />
        {openDeletion ? (
          <p className="text-sm">{t("privacy.deletion.pending", { date: formatDate(openDeletion.requested_at) })}</p>
        ) : (
          <div className="flex flex-col gap-3">
            <Field id="del-reason" label={t("privacy.deletion.reason")}>
              <Textarea
                id="del-reason"
                rows={2}
                maxLength={1000}
                value={reason}
                onChange={(e) => setReason(e.target.value)}
              />
            </Field>
            <div>
              <ConfirmDialog
                trigger={
                  <Button size="sm" variant="secondary">
                    <Trash2 /> {t("privacy.deletion.request")}
                  </Button>
                }
                title={t("privacy.deletion.confirmTitle")}
                description={t("privacy.deletion.confirmHint")}
                actionLabel={t("privacy.deletion.request")}
                onConfirm={(_, close) =>
                  run(
                    () => createPrivacyRequest({ kind: "deletion", reason }),
                    () => {
                      close();
                      router.refresh();
                    },
                  )
                }
              />
            </div>
          </div>
        )}
      </Card>
      {requests.length ? (
        <Card>
          <CardHeader title={t("privacy.history")} />
          <ul className="flex flex-col divide-y divide-line text-sm">
            {requests.map((r) => (
              <li key={r.id} className="flex flex-wrap items-center gap-2 py-2">
                <span className="font-medium">{t(`privacy.kinds.${r.kind}`)}</span>
                <StatusBadge status={r.status} label={t(`privacy.statuses.${r.status}`)} />
                <span className="text-xs text-muted">{formatDateTime(r.requested_at)}</span>
                {r.decision_note && r.status === "rejected" ? (
                  <span className="w-full text-xs text-muted">{r.decision_note}</span>
                ) : null}
              </li>
            ))}
          </ul>
        </Card>
      ) : null}
    </div>
  );
}
