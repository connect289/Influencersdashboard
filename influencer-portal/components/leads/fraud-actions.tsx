"use client";
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { useAction } from "@/components/ui/use-action";
import { decideFraudFlag } from "@/lib/actions/links";

/** Clear a flag (the credit stands) or confirm it (the attribution is rejected). A reason is always recorded. */
export function FraudActions({ flagId }: { flagId: string }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const decide = (confirm: boolean) => (reason: string, close: () => void) =>
    run(
      () => decideFraudFlag({ flagId, confirm, note: reason }),
      () => (close(), router.refresh()),
    );
  return (
    <div className="flex gap-2">
      <ConfirmDialog
        trigger={
          <Button size="sm" variant="secondary">
            {t("leads.fraud.clear")}
          </Button>
        }
        title={t("leads.fraud.clearTitle")}
        description={t("leads.fraud.clearHint")}
        actionLabel={t("leads.fraud.clear")}
        reasonLabel={t("leads.override.reason")}
        danger={false}
        pending={pending}
        onConfirm={decide(false)}
      />
      <ConfirmDialog
        trigger={
          <Button size="sm" variant="ghost">
            {t("leads.fraud.confirm")}
          </Button>
        }
        title={t("leads.fraud.confirmTitle")}
        description={t("leads.fraud.confirmHint")}
        actionLabel={t("leads.fraud.confirm")}
        reasonLabel={t("leads.override.reason")}
        pending={pending}
        onConfirm={decide(true)}
      />
    </div>
  );
}
