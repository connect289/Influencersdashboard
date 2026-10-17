"use client";
// Finance ledger actions: post an adjustment, hold or release an entry, hold or release all of a creator's entries.
import { Plus } from "lucide-react";
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Input, Select, Textarea } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { holdCreator, holdEntry, postAdjustment } from "@/lib/actions/ledger";
import { TDS_COMPONENTS, type TdsComponent } from "@/lib/compensation/tax";

export function AdjustmentDialog({
  creators,
  creatorId,
}: {
  creators: readonly { id: string; name: string }[];
  creatorId: string | null;
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [open, setOpen] = useState(false);
  const [creator, setCreator] = useState(creatorId ?? "");
  const [direction, setDirection] = useState<"credit" | "debit">("credit");
  const [amount, setAmount] = useState("");
  const [component, setComponent] = useState<TdsComponent>("commission");
  const [reason, setReason] = useState("");
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm">
          <Plus /> {t("finance.ledger.adjust")}
        </Button>
      </DialogTrigger>
      <DialogContent title={t("finance.ledger.adjustTitle")} closeLabel={t("common.close")}>
        <form
          className="flex flex-col gap-3"
          onSubmit={(e) => {
            e.preventDefault();
            run(
              () =>
                postAdjustment({
                  creatorId: creator,
                  direction,
                  amountRupees: Number(amount),
                  component,
                  reason,
                }),
              () => {
                setOpen(false);
                setAmount("");
                setReason("");
                router.refresh();
              },
            );
          }}
        >
          <Field id="adj-creator" label={t("finance.ledger.columns.creator")} required>
            <Select id="adj-creator" required value={creator} onChange={(e) => setCreator(e.target.value)}>
              <option value="">{t("finance.ledger.pickCreator")}</option>
              {creators.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </Select>
          </Field>
          <div className="grid gap-3 sm:grid-cols-2">
            <Field id="adj-direction" label={t("finance.ledger.direction")}>
              <Select
                id="adj-direction"
                value={direction}
                onChange={(e) => setDirection(e.target.value as "credit" | "debit")}
              >
                <option value="credit">{t("finance.ledger.credit")}</option>
                <option value="debit">{t("finance.ledger.debit")}</option>
              </Select>
            </Field>
            <Field id="adj-amount" label={t("finance.ledger.amountRupees")} required>
              <Input
                id="adj-amount"
                inputMode="decimal"
                required
                value={amount}
                onChange={(e) => setAmount(e.target.value.replace(/[^0-9.]/g, ""))}
              />
            </Field>
          </div>
          <Field id="adj-component" label={t("finance.ledger.component")} hint={t("finance.ledger.componentHint")}>
            <Select id="adj-component" value={component} onChange={(e) => setComponent(e.target.value as TdsComponent)}>
              {TDS_COMPONENTS.filter((c) => c !== "non_cash").map((c) => (
                <option key={c} value={c}>
                  {t(`finance.components.${c}`)}
                </option>
              ))}
            </Select>
          </Field>
          <Field id="adj-reason" label={t("finance.reason")} required>
            <Textarea
              id="adj-reason"
              required
              minLength={3}
              maxLength={500}
              rows={2}
              value={reason}
              onChange={(e) => setReason(e.target.value)}
            />
          </Field>
          <div className="flex justify-end">
            <Button type="submit" disabled={pending || !creator || !(Number(amount) > 0) || reason.trim().length < 3}>
              {t("finance.ledger.post")}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}

export function HoldButton({ entryId, held }: { entryId: number; held: boolean }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  return (
    <ConfirmDialog
      trigger={
        <Button size="sm" variant="ghost">
          {held ? t("finance.ledger.release") : t("finance.ledger.hold")}
        </Button>
      }
      title={held ? t("finance.ledger.releaseTitle") : t("finance.ledger.holdTitle")}
      actionLabel={held ? t("finance.ledger.release") : t("finance.ledger.hold")}
      reasonLabel={t("finance.reason")}
      pending={pending}
      onConfirm={(reason, close) =>
        run(
          () => holdEntry({ entryId, hold: !held, reason }),
          () => (close(), router.refresh()),
        )
      }
    />
  );
}

export function HoldCreatorButtons({ creatorId }: { creatorId: string }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  return (
    <span className="flex gap-1">
      {([true, false] as const).map((hold) => (
        <ConfirmDialog
          key={String(hold)}
          trigger={
            <Button size="sm" variant="ghost">
              {hold ? t("finance.ledger.holdAll") : t("finance.ledger.releaseAll")}
            </Button>
          }
          title={hold ? t("finance.ledger.holdAllTitle") : t("finance.ledger.releaseAllTitle")}
          actionLabel={hold ? t("finance.ledger.holdAll") : t("finance.ledger.releaseAll")}
          reasonLabel={t("finance.reason")}
          pending={pending}
          onConfirm={(reason, close) =>
            run(
              () => holdCreator({ creatorId, hold, reason }),
              () => (close(), router.refresh()),
            )
          }
        />
      ))}
    </span>
  );
}
