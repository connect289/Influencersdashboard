"use client";
import { useTranslations } from "next-intl";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { useAction } from "@/components/ui/use-action";
import { setCampaignStatus } from "@/lib/actions/campaigns";
import { STATUS_MOVES, type CampaignStatus } from "@/lib/campaigns/schemas";

/** The next statuses a campaign can move to. Completing and archiving ask for confirmation. */
export function CampaignStatusActions({
  campaignId,
  status,
}: {
  campaignId: string;
  status: CampaignStatus;
}) {
  const t = useTranslations();
  const { pending, run } = useAction();
  return (
    <div className="flex flex-wrap gap-2">
      {STATUS_MOVES[status].map((s) =>
        s === "completed" || s === "archived" ? (
          <ConfirmDialog
            key={s}
            title={t(`campaigns.moves.${s}`)}
            description={t(`campaigns.moveBodies.${s}`)}
            actionLabel={t(`campaigns.moves.${s}`)}
            pending={pending}
            onConfirm={(_, close) => run(() => setCampaignStatus(campaignId, s), close)}
            trigger={
              <Button size="sm" variant="secondary">
                {t(`campaigns.moves.${s}`)}
              </Button>
            }
          />
        ) : (
          <Button
            key={s}
            size="sm"
            variant={s === "open" || s === "active" ? "primary" : "secondary"}
            disabled={pending}
            onClick={() => run(() => setCampaignStatus(campaignId, s))}
          >
            {t(`campaigns.moves.${s}`)}
          </Button>
        ),
      )}
    </div>
  );
}
