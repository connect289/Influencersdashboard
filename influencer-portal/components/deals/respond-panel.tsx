"use client";
// The creator (or their negotiating agency) accepts or declines proposed terms.
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { useAction } from "@/components/ui/use-action";
import { respondToTerms } from "@/lib/actions/deals";

export function RespondPanel({
  dealId,
  versionId,
  amendment,
}: {
  dealId: string;
  versionId: string;
  amendment: boolean;
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  return (
    <div className="flex flex-wrap gap-2">
      <ConfirmDialog
        trigger={<Button>{t("deals.respond.accept")}</Button>}
        title={amendment ? t("deals.respond.acceptAmendment") : t("deals.respond.acceptTitle")}
        description={t("deals.respond.acceptHint")}
        actionLabel={t("deals.respond.accept")}
        danger={false}
        pending={pending}
        onConfirm={(_r, close) =>
          run(
            () => respondToTerms({ versionId, accept: true }, dealId),
            () => {
              close();
              router.refresh();
            },
          )
        }
      />
      <ConfirmDialog
        trigger={<Button variant="secondary">{t("deals.respond.decline")}</Button>}
        title={t("deals.respond.declineTitle")}
        description={t("deals.respond.declineHint")}
        actionLabel={t("deals.respond.decline")}
        reasonLabel={t("deals.respond.reason")}
        pending={pending}
        onConfirm={(reason, close) =>
          run(
            () => respondToTerms({ versionId, accept: false, reason }, dealId),
            () => {
              close();
              router.refresh();
            },
          )
        }
      />
    </div>
  );
}
