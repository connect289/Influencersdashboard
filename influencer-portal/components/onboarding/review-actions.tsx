"use client";
import { useTranslations } from "next-intl";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { useAction } from "@/components/ui/use-action";
import { reviewCreator } from "@/lib/actions/onboarding";

/** Approve, ask for changes, or decline a creator who finished onboarding. */
export function ReviewActions({ creatorId, name }: { creatorId: string; name: string }) {
  const t = useTranslations();
  const { pending, run } = useAction();
  return (
    <div className="flex flex-wrap gap-2">
      <Button
        size="sm"
        disabled={pending}
        onClick={() => run(() => reviewCreator({ creatorId, decision: "approve", reason: "" }))}
      >
        {t("onboarding.review.approve")}
      </Button>
      <ConfirmDialog
        title={t("onboarding.review.changesTitle", { name })}
        description={t("onboarding.review.changesBody")}
        reasonLabel={t("onboarding.review.whatToChange")}
        actionLabel={t("onboarding.review.changes")}
        danger={false}
        pending={pending}
        onConfirm={(reason, close) => run(() => reviewCreator({ creatorId, decision: "changes", reason }), close)}
        trigger={
          <Button size="sm" variant="secondary">
            {t("onboarding.review.changes")}
          </Button>
        }
      />
      <ConfirmDialog
        title={t("onboarding.review.declineTitle", { name })}
        description={t("onboarding.review.declineBody")}
        reasonLabel={t("creators.blockReason")}
        actionLabel={t("onboarding.review.decline")}
        pending={pending}
        onConfirm={(reason, close) => run(() => reviewCreator({ creatorId, decision: "decline", reason }), close)}
        trigger={
          <Button size="sm" variant="ghost">
            {t("onboarding.review.decline")}
          </Button>
        }
      />
    </div>
  );
}
