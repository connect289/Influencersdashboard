"use client";
// Staff actions on a deal: propose the working copy (or an amendment), withdraw an open proposal, start an
// amendment, move the status, delete an unproposed draft.
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Input, Textarea } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import {
  deleteDraftDeal,
  proposeDeal,
  renewDeal,
  setDealStatus,
  updateDeal,
  withdrawProposal,
} from "@/lib/actions/deals";
import type { CompConfig } from "@/lib/compensation/schema";
import { DEAL_MOVES, type DealStatus } from "@/lib/deals/schemas";

function ProposeDialog({ dealId, amendment }: { dealId: string; amendment: boolean }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [open, setOpen] = useState(false);
  const [note, setNote] = useState("");
  const [effectiveFrom, setEffectiveFrom] = useState("");
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button>
          {amendment ? t("deals.actions.proposeAmendment") : t("deals.actions.propose")}
        </Button>
      </DialogTrigger>
      <DialogContent
        title={amendment ? t("deals.actions.proposeAmendment") : t("deals.actions.propose")}
        description={
          amendment ? t("deals.actions.proposeAmendmentHint") : t("deals.actions.proposeHint")
        }
        closeLabel={t("common.close")}
      >
        <form
          className="flex flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            run(
              () => proposeDeal({ dealId, note, effectiveFrom: amendment ? effectiveFrom : "" }),
              () => {
                setOpen(false);
                router.refresh();
              },
            );
          }}
        >
          {amendment ? (
            <Field
              id="eff-from"
              label={t("deals.actions.effectiveFrom")}
              hint={t("deals.actions.effectiveFromHint")}
            >
              <Input
                id="eff-from"
                type="datetime-local"
                value={effectiveFrom}
                onChange={(e) => setEffectiveFrom(e.target.value)}
              />
            </Field>
          ) : null}
          <Field id="prop-note" label={t("deals.actions.note")}>
            <Textarea
              id="prop-note"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              maxLength={1000}
            />
          </Field>
          <div className="flex justify-end">
            <Button type="submit" disabled={pending}>
              {t("deals.actions.send")}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function RenewDialog({ dealId }: { dealId: string }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [open, setOpen] = useState(false);
  const [startsOn, setStartsOn] = useState("");
  const [endsOn, setEndsOn] = useState("");
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="secondary">{t("deals.actions.renew")}</Button>
      </DialogTrigger>
      <DialogContent
        title={t("deals.actions.renew")}
        description={t("deals.actions.renewHint")}
        closeLabel={t("common.close")}
      >
        <form
          className="flex flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            run(
              () => renewDeal({ dealId, startsOn, endsOn }),
              (d) => {
                setOpen(false);
                if (d) router.push(`/admin/deals/${d.id}?tab=terms`);
              },
            );
          }}
        >
          <Field id="rn-start" label={t("deals.new.startsOn")} required>
            <Input
              id="rn-start"
              type="date"
              value={startsOn}
              onChange={(e) => setStartsOn(e.target.value)}
              required
            />
          </Field>
          <Field id="rn-end" label={t("deals.new.endsOn")}>
            <Input
              id="rn-end"
              type="date"
              value={endsOn}
              onChange={(e) => setEndsOn(e.target.value)}
            />
          </Field>
          <div className="flex justify-end">
            <Button type="submit" disabled={pending || !startsOn}>
              {t("deals.actions.renew")}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}

export function DealActions({
  dealId,
  status,
  hasDraft,
  pendingVersionId,
  currentConfig,
  hasVersions,
}: {
  dealId: string;
  status: DealStatus;
  hasDraft: boolean;
  pendingVersionId: string | null;
  currentConfig: CompConfig | null;
  hasVersions: boolean;
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const open = ["draft", "negotiating", "agreed", "active"].includes(status);
  return (
    <div className="flex flex-wrap gap-2">
      {open && hasDraft && !pendingVersionId ? (
        <ProposeDialog dealId={dealId} amendment={currentConfig !== null} />
      ) : null}
      {pendingVersionId ? (
        <ConfirmDialog
          trigger={<Button variant="secondary">{t("deals.actions.withdraw")}</Button>}
          title={t("deals.actions.withdraw")}
          description={t("deals.actions.withdrawHint")}
          actionLabel={t("deals.actions.withdraw")}
          pending={pending}
          onConfirm={(_r, close) =>
            run(
              () => withdrawProposal(pendingVersionId, dealId),
              () => {
                close();
                router.refresh();
              },
            )
          }
        />
      ) : null}
      {(status === "agreed" || status === "active") &&
      !hasDraft &&
      !pendingVersionId &&
      currentConfig ? (
        <Button
          variant="secondary"
          disabled={pending}
          onClick={() =>
            run(
              () => updateDeal({ dealId, config: currentConfig }),
              () => router.push(`/admin/deals/${dealId}?tab=terms`),
            )
          }
        >
          {t("deals.actions.amend")}
        </Button>
      ) : null}
      {DEAL_MOVES[status].map((to) => (
        <ConfirmDialog
          key={to}
          trigger={
            <Button variant={to === "terminated" ? "danger" : "secondary"}>
              {t(`deals.moves.${to}`)}
            </Button>
          }
          title={t(`deals.moves.${to}`)}
          description={t(`deals.moveHints.${to}`)}
          actionLabel={t(`deals.moves.${to}`)}
          danger={to === "terminated"}
          reasonLabel={
            to === "active" || to === "terminated" ? t("deals.actions.reason") : undefined
          }
          pending={pending}
          onConfirm={(reason, close) =>
            run(
              () => setDealStatus({ dealId, status: to, reason }),
              () => {
                close();
                router.refresh();
              },
            )
          }
        />
      ))}
      {["active", "completed", "expired"].includes(status) && currentConfig ? (
        <RenewDialog dealId={dealId} />
      ) : null}
      {status === "draft" && !hasVersions ? (
        <ConfirmDialog
          trigger={<Button variant="ghost">{t("deals.actions.delete")}</Button>}
          title={t("deals.actions.delete")}
          description={t("deals.actions.deleteHint")}
          actionLabel={t("deals.actions.delete")}
          pending={pending}
          onConfirm={(_r, close) =>
            run(
              () => deleteDraftDeal(dealId),
              () => {
                close();
                router.push("/admin/deals");
              },
            )
          }
        />
      ) : null}
    </div>
  );
}
