"use client";
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { useAction } from "@/components/ui/use-action";
import { decidePenalty } from "@/lib/actions/content";

/** Approve (applied with the ledger in Phase 7) or reject with a reason. */
export function PenaltyActions({ id }: { id: string }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  return (
    <div className="flex gap-2">
      <ConfirmDialog
        trigger={<Button size="sm">{t("content.penalties.approve")}</Button>}
        title={t("content.penalties.approveTitle")}
        description={t("content.penalties.approveHint")}
        actionLabel={t("content.penalties.approve")}
        danger={false}
        pending={pending}
        onConfirm={(_, close) =>
          run(
            () => decidePenalty({ id, approve: true }),
            () => {
              close();
              router.refresh();
            },
          )
        }
      />
      <ConfirmDialog
        trigger={
          <Button size="sm" variant="ghost">
            {t("content.penalties.reject")}
          </Button>
        }
        title={t("content.penalties.rejectTitle")}
        actionLabel={t("content.penalties.reject")}
        reasonLabel={t("content.checks.reason")}
        pending={pending}
        onConfirm={(reason, close) =>
          run(
            () => decidePenalty({ id, approve: false, note: reason }),
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
