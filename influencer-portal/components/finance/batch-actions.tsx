"use client";
// Payout batch actions (Finance): prepare, approve, cancel, mark paid (one payout or the bank's UTR file), mark a
// payout failed, remove a payout from a draft batch.
import { CheckCheck, FileUp, Plus } from "lucide-react";
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Input, Select } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import {
  approveBatch,
  cancelBatch,
  markFailed,
  markPaid,
  markPaidFromFile,
  prepareBatch,
  removePayout,
} from "@/lib/actions/payouts";

export function PrepareBatchForm({
  campaigns,
  today,
}: {
  campaigns: readonly { id: string; name: string }[];
  today: string;
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [campaign, setCampaign] = useState("");
  const [dueBy, setDueBy] = useState(today);
  const [note, setNote] = useState("");
  return (
    <form
      className="flex flex-wrap items-end gap-3"
      onSubmit={(e) => {
        e.preventDefault();
        run(
          () => prepareBatch({ campaignId: campaign || null, dueBy, note }),
          (d) => d && router.push(`/admin/finance/payouts/${d.id}`),
        );
      }}
    >
      <Field id="pb-campaign" label={t("finance.payouts.campaign")}>
        <Select id="pb-campaign" value={campaign} onChange={(e) => setCampaign(e.target.value)}>
          <option value="">{t("finance.payouts.allCampaigns")}</option>
          {campaigns.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </Select>
      </Field>
      <Field id="pb-due" label={t("finance.payouts.dueBy")}>
        <Input id="pb-due" type="date" max={today} value={dueBy} onChange={(e) => setDueBy(e.target.value)} />
      </Field>
      <Field id="pb-note" label={t("finance.payouts.note")} className="min-w-48 flex-1">
        <Input id="pb-note" maxLength={500} value={note} onChange={(e) => setNote(e.target.value)} />
      </Field>
      <Button type="submit" disabled={pending}>
        <Plus /> {t("finance.payouts.prepare")}
      </Button>
    </form>
  );
}

export function ApproveButton({ batchId, label }: { batchId: string; label: string }) {
  const router = useRouter();
  const { pending, run } = useAction();
  return (
    <Button
      size="sm"
      disabled={pending}
      onClick={() =>
        run(
          () => approveBatch(batchId),
          () => router.refresh(),
        )
      }
    >
      <CheckCheck /> {label}
    </Button>
  );
}

export function CancelBatchButton({ batchId }: { batchId: string }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  return (
    <ConfirmDialog
      trigger={
        <Button size="sm" variant="ghost">
          {t("finance.payouts.cancel")}
        </Button>
      }
      title={t("finance.payouts.cancelTitle")}
      description={t("finance.payouts.cancelHint")}
      actionLabel={t("finance.payouts.cancel")}
      reasonLabel={t("finance.reason")}
      danger
      pending={pending}
      onConfirm={(reason, close) =>
        run(
          () => cancelBatch({ id: batchId, reason }),
          () => (close(), router.refresh()),
        )
      }
    />
  );
}

export function UtrFileButton() {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const input = useRef<HTMLInputElement>(null);
  return (
    <>
      <input
        ref={input}
        type="file"
        accept=".csv,text/csv"
        className="sr-only"
        aria-label={t("finance.payouts.utrFile")}
        onChange={(e) => {
          const f = e.target.files?.[0];
          e.target.value = "";
          if (!f) return;
          void f.text().then((text) =>
            run(
              () => markPaidFromFile({ text }),
              () => router.refresh(),
            ),
          );
        }}
      />
      <Button size="sm" variant="secondary" disabled={pending} onClick={() => input.current?.click()}>
        <FileUp /> {t("finance.payouts.utrFile")}
      </Button>
    </>
  );
}

export function MarkPaidDialog({ payoutRef, today }: { payoutRef: string; today: string }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [open, setOpen] = useState(false);
  const [utr, setUtr] = useState("");
  const [paidOn, setPaidOn] = useState(today);
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm" variant="secondary">
          {t("finance.payouts.markPaid")}
        </Button>
      </DialogTrigger>
      <DialogContent title={t("finance.payouts.markPaidTitle", { ref: payoutRef })} closeLabel={t("common.close")}>
        <form
          className="flex flex-col gap-3"
          onSubmit={(e) => {
            e.preventDefault();
            run(
              () => markPaid({ payoutRef, utr, paidOn }),
              () => (setOpen(false), router.refresh()),
            );
          }}
        >
          <Field id="mp-utr" label={t("finance.payouts.utr")} hint={t("finance.payouts.utrHint")} required>
            <Input
              id="mp-utr"
              required
              autoComplete="off"
              maxLength={22}
              value={utr}
              onChange={(e) => setUtr(e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, ""))}
            />
          </Field>
          <Field id="mp-date" label={t("finance.payouts.paidOn")} required>
            <Input
              id="mp-date"
              type="date"
              required
              max={today}
              value={paidOn}
              onChange={(e) => setPaidOn(e.target.value)}
            />
          </Field>
          <div className="flex justify-end">
            <Button type="submit" disabled={pending || utr.length < 12}>
              {t("finance.payouts.markPaid")}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}

export function PayoutReasonButton({ payoutId, kind }: { payoutId: string; kind: "remove" | "fail" }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  return (
    <ConfirmDialog
      trigger={
        <Button size="sm" variant="ghost">
          {t(`finance.payouts.${kind}`)}
        </Button>
      }
      title={t(`finance.payouts.${kind}Title`)}
      description={t(`finance.payouts.${kind}Hint`)}
      actionLabel={t(`finance.payouts.${kind}`)}
      reasonLabel={t("finance.reason")}
      danger
      pending={pending}
      onConfirm={(reason, close) =>
        run(
          () => (kind === "remove" ? removePayout({ id: payoutId, reason }) : markFailed({ id: payoutId, reason })),
          () => (close(), router.refresh()),
        )
      }
    />
  );
}
