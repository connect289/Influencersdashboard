"use client";
import { useTranslations } from "next-intl";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { useAction } from "@/components/ui/use-action";
import { revokeAgencyLink } from "@/lib/actions/agency";

export function LinkRevoke({ linkId, name }: { linkId: string; name: string }) {
  const t = useTranslations();
  const { pending, run } = useAction();
  return (
    <ConfirmDialog
      title={t("agencies.links.revokeTitle", { name })}
      description={t("agencies.links.revokeBody")}
      reasonLabel={t("agencies.links.reason")}
      actionLabel={t("agencies.links.revoke")}
      pending={pending}
      onConfirm={(reason, close) => run(() => revokeAgencyLink(linkId, reason), close)}
      trigger={
        <Button variant="ghost" size="sm">
          {t("agencies.links.revoke")}
        </Button>
      }
    />
  );
}
