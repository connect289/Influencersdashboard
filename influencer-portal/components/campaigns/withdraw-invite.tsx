"use client";
import { useTranslations } from "next-intl";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { useAction } from "@/components/ui/use-action";
import { withdrawInvite } from "@/lib/actions/campaigns";

export function WithdrawInviteButton({ inviteId }: { inviteId: string }) {
  const t = useTranslations();
  const { pending, run } = useAction();
  return (
    <ConfirmDialog
      title={t("campaigns.invites.withdrawTitle")}
      actionLabel={t("campaigns.invites.withdraw")}
      pending={pending}
      onConfirm={(_, close) => run(() => withdrawInvite(inviteId), close)}
      trigger={
        <Button size="sm" variant="ghost">
          {t("campaigns.invites.withdraw")}
        </Button>
      }
    />
  );
}
