"use client";
// Finance records Eduwit's commission received for an enrolment by hand (or withdraws an earlier override).
import { Plus } from "lucide-react";
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Input, Select, Textarea } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { recordReceipt } from "@/lib/actions/ledger";
import { RECEIPT_STATUSES } from "@/lib/ledger/schemas";

export function ReceiptDialog({ enrollmentRef = "", label }: { enrollmentRef?: string; label?: string }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [open, setOpen] = useState(false);
  const [ref, setRef] = useState(enrollmentRef);
  const [lead, setLead] = useState("");
  const [status, setStatus] = useState<(typeof RECEIPT_STATUSES)[number]>("received");
  const [gross, setGross] = useState("");
  const [received, setReceived] = useState("");
  const [on, setOn] = useState("");
  const [reason, setReason] = useState("");
  const num = (s: string) => (s === "" ? 0 : Number(s));
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm" variant={enrollmentRef ? "ghost" : "primary"}>
          {enrollmentRef ? null : <Plus />} {label ?? t("finance.receipts.record")}
        </Button>
      </DialogTrigger>
      <DialogContent title={t("finance.receipts.recordTitle")} closeLabel={t("common.close")}>
        <form
          className="flex flex-col gap-3"
          onSubmit={(e) => {
            e.preventDefault();
            run(
              () =>
                recordReceipt({
                  enrollmentRef: ref.trim(),
                  studentLeadId: lead ? Number(lead) : null,
                  status,
                  grossRupees: num(gross),
                  receivedRupees: num(received),
                  receivedOn: on || null,
                  reason,
                }),
              () => (setOpen(false), router.refresh()),
            );
          }}
        >
          <div className="grid gap-3 sm:grid-cols-2">
            <Field
              id="rc-ref"
              label={t("finance.receipts.enrolment")}
              hint={t("finance.receipts.enrolmentHint")}
              required
            >
              <Input
                id="rc-ref"
                required
                value={ref}
                readOnly={!!enrollmentRef}
                onChange={(e) => setRef(e.target.value)}
              />
            </Field>
            {enrollmentRef ? null : (
              <Field id="rc-lead" label={t("finance.receipts.leadId")} hint={t("finance.receipts.leadIdHint")}>
                <Input
                  id="rc-lead"
                  inputMode="numeric"
                  value={lead}
                  onChange={(e) => setLead(e.target.value.replace(/\D/g, ""))}
                />
              </Field>
            )}
          </div>
          <Field id="rc-status" label={t("finance.receipts.status")}>
            <Select
              id="rc-status"
              value={status}
              onChange={(e) => setStatus(e.target.value as (typeof RECEIPT_STATUSES)[number])}
            >
              {RECEIPT_STATUSES.map((s) => (
                <option key={s} value={s}>
                  {t(`finance.receiptStatuses.${s}`)}
                </option>
              ))}
            </Select>
          </Field>
          {status !== "withdrawn" ? (
            <div className="grid gap-3 sm:grid-cols-3">
              <Field id="rc-gross" label={t("finance.receipts.expected")}>
                <Input
                  id="rc-gross"
                  inputMode="decimal"
                  value={gross}
                  onChange={(e) => setGross(e.target.value.replace(/[^0-9.]/g, ""))}
                />
              </Field>
              <Field id="rc-received" label={t("finance.receipts.received")}>
                <Input
                  id="rc-received"
                  inputMode="decimal"
                  value={received}
                  onChange={(e) => setReceived(e.target.value.replace(/[^0-9.]/g, ""))}
                />
              </Field>
              <Field id="rc-on" label={t("finance.receipts.receivedOn")}>
                <Input id="rc-on" type="date" value={on} onChange={(e) => setOn(e.target.value)} />
              </Field>
            </div>
          ) : (
            <p className="text-sm text-muted">{t("finance.receipts.withdrawHint")}</p>
          )}
          <Field id="rc-reason" label={t("finance.reason")} required>
            <Textarea
              id="rc-reason"
              rows={2}
              required
              minLength={3}
              maxLength={500}
              value={reason}
              onChange={(e) => setReason(e.target.value)}
            />
          </Field>
          <div className="flex justify-end">
            <Button type="submit" disabled={pending || reason.trim().length < 3 || !/^(b2b|b2c):\d+$/.test(ref.trim())}>
              {t("finance.receipts.save")}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
