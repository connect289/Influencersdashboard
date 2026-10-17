"use client";
import { useTranslations } from "next-intl";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { useAction } from "@/components/ui/use-action";
import { setAgencyStatus } from "@/lib/actions/agency";

export function AgencyStatusButton({ agencyId, status, name }: { agencyId: string; status: string; name: string }) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const next = status === "active" ? "suspended" : "active";
  return (
    <ConfirmDialog
      title={next === "suspended" ? t("agencies.suspendTitle", { name }) : t("agencies.reactivateTitle", { name })}
      description={next === "suspended" ? t("agencies.suspendBody") : undefined}
      reasonLabel={t("agencies.links.reason")}
      actionLabel={next === "suspended" ? t("agencies.suspend") : t("agencies.reactivate")}
      danger={next === "suspended"}
      pending={pending}
      onConfirm={(reason, close) => run(() => setAgencyStatus(agencyId, next, reason), close)}
      trigger={
        <Button variant="secondary" size="sm">
          {next === "suspended" ? t("agencies.suspend") : t("agencies.reactivate")}
        </Button>
      }
    />
  );
}
