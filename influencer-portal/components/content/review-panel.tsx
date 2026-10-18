"use client";
// Staff review of the latest submission: the automatic compliance checks (with override), the ASCI checklist at
// the last approval before publishing, approve or ask for changes within the revision limit, and extra rounds.
import { AlertTriangle, CheckCircle2, RefreshCw, ShieldAlert } from "lucide-react";
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { Field } from "@/components/ui/field";
import { Input, Textarea } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import {
  decideExtension,
  overrideCheck,
  requestExtension,
  rescanSubmission,
  reviewSubmission,
} from "@/lib/actions/content";
import { ASCI_CHECKLIST, type AsciItem } from "@/lib/content/compliance";
import type { ComplianceCheck, RevisionExtension, Submission } from "@/lib/content/data";
import { formatDate, formatPaise } from "@/lib/format";

type Match = { text: string; severity: "block" | "warn"; note: string | null };

function matchesOf(c: ComplianceCheck): Match[] {
  const raw = c.result.claims;
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((m: unknown) => {
    if (typeof m !== "object" || m === null) return [];
    const o = m as Record<string, unknown>;
    return typeof o.text === "string"
      ? [
          {
            text: o.text,
            severity: o.severity === "warn" ? "warn" : "block",
            note: typeof o.note === "string" ? o.note : null,
          },
        ]
      : [];
  });
}

export function ChecksList({
  deliverableId,
  checks,
  canOverride,
  canRescan,
  submissionId,
}: {
  deliverableId: string;
  checks: ComplianceCheck[];
  canOverride: boolean;
  canRescan: boolean;
  submissionId: string;
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  // The newest result of each kind counts.
  const latest = (["banned_claims", "disclosure"] as const)
    .map((k) => checks.filter((c) => c.kind === k && c.submission_id === submissionId).at(-1))
    .filter((c): c is ComplianceCheck => c !== undefined);
  return (
    <div className="flex flex-col gap-2">
      {latest.length === 0 ? (
        <p className="flex items-center gap-2 text-sm text-muted">
          <AlertTriangle className="size-4" aria-hidden /> {t("content.review.scanMissing")}
        </p>
      ) : null}
      {latest.map((c) => {
        const ok = c.passed || c.overridden;
        const matches = matchesOf(c);
        return (
          <div
            key={c.id}
            className={ok ? "rounded-xl bg-success-soft p-3 text-sm" : "rounded-xl bg-danger-soft p-3 text-sm"}
          >
            <p className="flex flex-wrap items-center gap-2 font-medium">
              {ok ? (
                <CheckCircle2 className="size-4 text-success" aria-hidden />
              ) : (
                <ShieldAlert className="size-4 text-danger" aria-hidden />
              )}
              {t(`content.checks.${c.kind}`)}:{" "}
              {c.passed
                ? t("content.checks.passed")
                : c.overridden
                  ? t("content.checks.overridden")
                  : t("content.checks.failed")}
            </p>
            {c.kind === "banned_claims" && matches.length ? (
              <ul className="mt-1 flex flex-col gap-0.5">
                {matches.map((m, i) => (
                  <li key={i}>
                    <Badge family={m.severity === "block" ? "problem" : "attention"}>
                      {t(`content.checks.severity.${m.severity}`)}
                    </Badge>{" "}
                    “{m.text}”{m.note ? <span className="text-muted"> — {m.note}</span> : null}
                  </li>
                ))}
              </ul>
            ) : null}
            {c.kind === "disclosure" && !c.passed ? (
              <p className="mt-1">{t("content.checks.disclosureMissing")}</p>
            ) : null}
            {c.overridden && c.override_reason ? (
              <p className="mt-1 text-muted">{t("content.checks.overrideReason", { reason: c.override_reason })}</p>
            ) : null}
            {!ok && canOverride ? (
              <ConfirmDialog
                trigger={
                  <Button size="sm" variant="secondary" className="mt-2">
                    {t("content.checks.override")}
                  </Button>
                }
                title={t("content.checks.overrideTitle")}
                description={t("content.checks.overrideHint")}
                actionLabel={t("content.checks.override")}
                reasonLabel={t("content.checks.reason")}
                pending={pending}
                onConfirm={(reason, close) =>
                  run(
                    () => overrideCheck({ checkId: c.id, reason, deliverableId }),
                    () => {
                      close();
                      router.refresh();
                    },
                  )
                }
              />
            ) : null}
          </div>
        );
      })}
      {canRescan ? (
        <Button
          type="button"
          variant="ghost"
          size="sm"
          className="self-start"
          disabled={pending}
          onClick={() =>
            run(
              () => rescanSubmission(submissionId),
              () => router.refresh(),
            )
          }
        >
          <RefreshCw /> {t("content.review.rescan")}
        </Button>
      ) : null}
    </div>
  );
}

export function ReviewPanel({
  deliverableId,
  submission,
  checks,
  needsChecklist,
  revisionsLeft,
  canOverride,
  canExtend,
  extensions,
}: {
  deliverableId: string;
  submission: Submission;
  checks: ComplianceCheck[];
  /** The last approval before publishing: the ASCI checklist must be complete. */
  needsChecklist: boolean;
  revisionsLeft: number;
  canOverride: boolean;
  canExtend: boolean;
  extensions: RevisionExtension[];
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [note, setNote] = useState("");
  const [list, setList] = useState<Record<AsciItem, boolean>>(
    Object.fromEntries(ASCI_CHECKLIST.map((k) => [k, false])) as Record<AsciItem, boolean>,
  );
  const [extReason, setExtReason] = useState("");
  const [extFee, setExtFee] = useState("");
  const done = ASCI_CHECKLIST.every((k) => list[k]);
  const pendingExt = extensions.find((e) => e.status === "pending");
  return (
    <Card className="flex flex-col gap-4">
      <CardHeader
        title={t("content.review.title", {
          kind: t(`content.kinds.${submission.kind}`),
          version: submission.version,
        })}
        description={t("content.review.revisions", { left: Math.max(0, revisionsLeft) })}
      />
      <ChecksList
        deliverableId={deliverableId}
        checks={checks}
        canOverride={canOverride}
        canRescan
        submissionId={submission.id}
      />
      {needsChecklist ? (
        <fieldset className="flex flex-col gap-2 rounded-xl p-3 ring-1 ring-line">
          <legend className="px-1 text-sm font-medium">{t("content.asci.title")}</legend>
          <p className="text-xs text-muted">{t("content.asci.hint")}</p>
          {ASCI_CHECKLIST.map((k) => (
            <label key={k} className="flex items-start gap-2 text-sm">
              <input
                type="checkbox"
                className="mt-0.5 size-4"
                checked={list[k]}
                onChange={(e) => setList({ ...list, [k]: e.target.checked })}
              />
              <span>{t(`content.asci.items.${k}`)}</span>
            </label>
          ))}
        </fieldset>
      ) : null}
      <Field id="rv-note" label={t("content.review.note")} hint={t("content.review.noteHint")}>
        <Textarea id="rv-note" rows={3} maxLength={4000} value={note} onChange={(e) => setNote(e.target.value)} />
      </Field>
      <div className="flex flex-wrap gap-2">
        <Button
          type="button"
          disabled={pending || (needsChecklist && !done)}
          onClick={() =>
            run(
              () =>
                reviewSubmission({
                  deliverableId,
                  submissionId: submission.id,
                  decision: "approve",
                  note,
                  checklist: needsChecklist ? list : null,
                }),
              () => {
                setNote("");
                router.refresh();
              },
            )
          }
        >
          {t("content.review.approve")}
        </Button>
        <Button
          type="button"
          variant="secondary"
          disabled={pending || note.trim().length < 3 || revisionsLeft <= 0}
          onClick={() =>
            run(
              () =>
                reviewSubmission({
                  deliverableId,
                  submissionId: submission.id,
                  decision: "changes",
                  note,
                }),
              () => {
                setNote("");
                router.refresh();
              },
            )
          }
        >
          {t("content.review.requestChanges")}
        </Button>
      </div>
      {revisionsLeft <= 0 ? (
        <div className="flex flex-col gap-2 rounded-xl bg-accent-soft p-3 text-sm">
          <p className="font-medium text-accent-ink">{t("content.extensions.limitReached")}</p>
          {pendingExt ? (
            <>
              <p>
                {t("content.extensions.pending", {
                  reason: pendingExt.reason,
                  fee: formatPaise(pendingExt.fee_paise),
                })}
              </p>
              {canExtend ? (
                <div className="flex gap-2">
                  <Button
                    size="sm"
                    disabled={pending}
                    onClick={() =>
                      run(
                        () => decideExtension({ id: pendingExt.id, approve: true, deliverableId }),
                        () => router.refresh(),
                      )
                    }
                  >
                    {t("content.extensions.approve")}
                  </Button>
                  <ConfirmDialog
                    trigger={
                      <Button size="sm" variant="ghost">
                        {t("content.extensions.reject")}
                      </Button>
                    }
                    title={t("content.extensions.rejectTitle")}
                    actionLabel={t("content.extensions.reject")}
                    reasonLabel={t("content.checks.reason")}
                    pending={pending}
                    onConfirm={(reason, close) =>
                      run(
                        () =>
                          decideExtension({
                            id: pendingExt.id,
                            approve: false,
                            note: reason,
                            deliverableId,
                          }),
                        () => {
                          close();
                          router.refresh();
                        },
                      )
                    }
                  />
                </div>
              ) : (
                <p className="text-muted">{t("content.extensions.waiting")}</p>
              )}
            </>
          ) : (
            <form
              className="grid gap-2 md:grid-cols-[2fr_1fr_auto] md:items-end"
              onSubmit={(e) => {
                e.preventDefault();
                run(
                  () =>
                    requestExtension({
                      deliverableId,
                      reason: extReason,
                      feePaise: Math.round((Number(extFee) || 0) * 100),
                    }),
                  () => {
                    setExtReason("");
                    setExtFee("");
                    router.refresh();
                  },
                );
              }}
            >
              <Field id="ext-reason" label={t("content.extensions.reason")}>
                <Input
                  id="ext-reason"
                  minLength={3}
                  maxLength={1000}
                  value={extReason}
                  onChange={(e) => setExtReason(e.target.value)}
                />
              </Field>
              <Field id="ext-fee" label={t("content.extensions.fee")} hint={t("content.extensions.feeHint")}>
                <Input
                  id="ext-fee"
                  type="number"
                  inputMode="decimal"
                  min={0}
                  step="1"
                  value={extFee}
                  onChange={(e) => setExtFee(e.target.value)}
                />
              </Field>
              <Button type="submit" size="sm" disabled={pending || extReason.trim().length < 3}>
                {t("content.extensions.request")}
              </Button>
            </form>
          )}
        </div>
      ) : null}
      {extensions.filter((e) => e.status !== "pending").length ? (
        <ul className="text-xs text-muted">
          {extensions
            .filter((e) => e.status !== "pending")
            .map((e) => (
              <li key={e.id}>
                {t(`content.extensions.history.${e.status === "approved" ? "approved" : "rejected"}`, {
                  date: formatDate(e.decided_at ?? e.requested_at),
                  reason: e.reason,
                })}
              </li>
            ))}
        </ul>
      ) : null}
    </Card>
  );
}
