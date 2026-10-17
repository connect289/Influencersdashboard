"use client";
// Staff actions on a contract: regenerate from the deal's current terms, send, mark ready to sign, void, and for an
// active contract terminate, complete or start an amendment.
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Textarea } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import {
  markReadyToSign,
  regenerateContract,
  sendContract,
  setContractStatus,
} from "@/lib/actions/contracts";
import type { ContractStatus } from "@/lib/contracts/data";

function RegenerateDialog({ contractId }: { contractId: string }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [open, setOpen] = useState(false);
  const [note, setNote] = useState("");
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="secondary">{t("contracts.actions.regenerate")}</Button>
      </DialogTrigger>
      <DialogContent
        title={t("contracts.actions.regenerate")}
        description={t("contracts.actions.regenerateHint")}
        closeLabel={t("common.close")}
      >
        <form
          className="flex flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            run(
              () => regenerateContract(contractId, note),
              () => {
                setOpen(false);
                setNote("");
                router.refresh();
              },
            );
          }}
        >
          <Field id="rg-note" label={t("contracts.actions.versionNote")}>
            <Textarea
              id="rg-note"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              maxLength={1000}
            />
          </Field>
          <div className="flex justify-end">
            <Button type="submit" disabled={pending}>
              {t("contracts.actions.regenerate")}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}

export function ContractActions({
  contractId,
  dealId,
  status,
  hasVersion,
  pendingRequests,
}: {
  contractId: string;
  dealId: string;
  status: ContractStatus;
  hasVersion: boolean;
  pendingRequests: number;
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const editable = ["draft", "sent", "in_negotiation", "ready_to_sign"].includes(status);
  const statusDialog = (to: "void" | "terminated" | "completed") => (
    <ConfirmDialog
      key={to}
      trigger={
        <Button variant={to === "completed" ? "secondary" : "danger"}>
          {t(`contracts.actions.${to}`)}
        </Button>
      }
      title={t(`contracts.actions.${to}`)}
      description={t(`contracts.actions.${to}Hint`)}
      reasonLabel={t("contracts.actions.reason")}
      actionLabel={t(`contracts.actions.${to}`)}
      danger={to !== "completed"}
      pending={pending}
      onConfirm={(reason, close) =>
        run(
          () => setContractStatus({ contractId, status: to, reason }),
          () => {
            close();
            router.refresh();
          },
        )
      }
    />
  );
  return (
    <>
      {editable ? <RegenerateDialog contractId={contractId} /> : null}
      {status === "draft" && hasVersion ? (
        <ConfirmDialog
          trigger={<Button>{t("contracts.actions.send")}</Button>}
          title={t("contracts.actions.send")}
          description={t("contracts.actions.sendHint")}
          actionLabel={t("contracts.actions.send")}
          danger={false}
          pending={pending}
          onConfirm={(_r, close) =>
            run(
              () => sendContract(contractId),
              () => {
                close();
                router.refresh();
              },
            )
          }
        />
      ) : null}
      {(status === "sent" || status === "in_negotiation") && hasVersion ? (
        <ConfirmDialog
          trigger={<Button disabled={pendingRequests > 0}>{t("contracts.actions.ready")}</Button>}
          title={t("contracts.actions.ready")}
          description={t("contracts.actions.readyHint")}
          actionLabel={t("contracts.actions.ready")}
          danger={false}
          pending={pending}
          onConfirm={(_r, close) =>
            run(
              () => markReadyToSign(contractId),
              () => {
                close();
                router.refresh();
              },
            )
          }
        />
      ) : null}
      {status === "active" ? (
        <>
          <Button asChild variant="secondary">
            <Link href={`/admin/contracts/new?deal=${dealId}&parent=${contractId}`}>
              {t("contracts.actions.amend")}
            </Link>
          </Button>
          {statusDialog("completed")}
          {statusDialog("terminated")}
        </>
      ) : null}
      {editable || status === "signed_by_creator" ? statusDialog("void") : null}
    </>
  );
}
