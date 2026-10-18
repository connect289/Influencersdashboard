"use client";
// Deal ledger actions: run the ledger now, release a manual milestone, record a breach.
import { Play } from "lucide-react";
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { useAction } from "@/components/ui/use-action";
import { recordManualEvent, runDealNow } from "@/lib/actions/ledger";

export function RunNowButton({ dealId }: { dealId: string }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  return (
    <Button
      size="sm"
      variant="secondary"
      disabled={pending}
      onClick={() =>
        run(
          () => runDealNow(dealId),
          () => router.refresh(),
        )
      }
    >
      <Play /> {t("finance.deal.runNow")}
    </Button>
  );
}

export function ReleaseMilestoneButton({
  dealId,
  milestone,
  label,
}: {
  dealId: string;
  milestone: string;
  label: string;
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  return (
    <ConfirmDialog
      trigger={
        <Button size="sm" variant="secondary">
          {t("finance.deal.release")}
        </Button>
      }
      title={t("finance.deal.releaseTitle", { milestone: label })}
      description={t("finance.deal.releaseHint")}
      actionLabel={t("finance.deal.release")}
      reasonLabel={t("finance.reason")}
      pending={pending}
      onConfirm={(reason, close) =>
        run(
          () => recordManualEvent({ dealId, kind: "manual_release", ref: milestone, reason }),
          () => (close(), router.refresh()),
        )
      }
    />
  );
}

export function RecordBreachButton({ dealId }: { dealId: string }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  return (
    <ConfirmDialog
      trigger={
        <Button size="sm" variant="ghost">
          {t("finance.deal.breach")}
        </Button>
      }
      title={t("finance.deal.breachTitle")}
      description={t("finance.deal.breachHint")}
      actionLabel={t("finance.deal.breach")}
      reasonLabel={t("finance.reason")}
      danger
      pending={pending}
      onConfirm={(reason, close) =>
        run(
          () => recordManualEvent({ dealId, kind: "breach", ref: null, reason }),
          () => (close(), router.refresh()),
        )
      }
    />
  );
}
