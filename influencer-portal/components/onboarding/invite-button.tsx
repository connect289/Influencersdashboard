"use client";
import { Send } from "lucide-react";
import { useTranslations } from "next-intl";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { useAction } from "@/components/ui/use-action";
import { inviteCreators } from "@/lib/actions/onboarding";

export function InviteButton({
  creatorId,
  name,
  email,
  resend,
}: {
  creatorId: string;
  name: string;
  email: string;
  resend: boolean;
}) {
  const t = useTranslations();
  const { pending, run } = useAction();
  return (
    <ConfirmDialog
      title={
        resend
          ? t("onboarding.invite.resendTitle", { name })
          : t("onboarding.invite.title", { name })
      }
      description={t("onboarding.invite.body", { email })}
      actionLabel={t("onboarding.invite.send")}
      danger={false}
      pending={pending}
      onConfirm={(_, close) => run(() => inviteCreators([creatorId]), close)}
      trigger={
        <Button variant="secondary" size="sm">
          <Send /> {resend ? t("onboarding.invite.resend") : t("onboarding.invite.button")}
        </Button>
      }
    />
  );
}
