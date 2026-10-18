"use client";
import { MoreHorizontal } from "lucide-react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Select } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { deleteDraftCreator, setCreatorBlocked, setCreatorStage } from "@/lib/actions/creators";
import { PIPELINE_STAGES, type PipelineStage } from "@/lib/creators/crm";

/** Stage picker plus block / unblock / delete-draft for the Creator 360 header. */
export function CreatorActions({
  creatorId,
  name,
  stage,
  isBlocked,
  canDelete,
}: {
  creatorId: string;
  name: string;
  stage: string;
  isBlocked: boolean;
  canDelete: boolean;
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [confirm, setConfirm] = useState<"block" | "unblock" | "delete" | null>(null);
  return (
    <div className="flex items-center gap-2">
      <label className="sr-only" htmlFor="stage-select">
        {t("creators.table.stage")}
      </label>
      <Select
        id="stage-select"
        className="h-9 w-auto md:h-9"
        value={stage}
        disabled={pending || isBlocked}
        onChange={(e) => run(() => setCreatorStage(creatorId, e.target.value))}
      >
        {PIPELINE_STAGES.map((s: PipelineStage) => (
          <option key={s} value={s}>
            {t(`creators.stages.${s}`)}
          </option>
        ))}
      </Select>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="secondary" size="icon" aria-label={t("creators.moreActions", { name })}>
            <MoreHorizontal />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          {isBlocked ? (
            <DropdownMenuItem onSelect={() => setConfirm("unblock")}>{t("creators.unblock")}</DropdownMenuItem>
          ) : (
            <DropdownMenuItem onSelect={() => setConfirm("block")}>{t("creators.block")}</DropdownMenuItem>
          )}
          {canDelete ? (
            <DropdownMenuItem onSelect={() => setConfirm("delete")}>{t("creators.deleteDraft")}</DropdownMenuItem>
          ) : null}
        </DropdownMenuContent>
      </DropdownMenu>
      {confirm ? (
        <ConfirmDialog
          key={confirm}
          trigger={<span className="hidden" />}
          title={t(`creators.confirm.${confirm}.title`, { name })}
          description={t(`creators.confirm.${confirm}.body`)}
          reasonLabel={confirm === "block" ? t("creators.blockReason") : undefined}
          actionLabel={t(`creators.confirm.${confirm}.action`)}
          danger={confirm !== "unblock"}
          pending={pending}
          defaultOpen
          onClose={() => setConfirm(null)}
          onConfirm={(reason, close) =>
            run(
              () =>
                confirm === "delete"
                  ? deleteDraftCreator(creatorId)
                  : setCreatorBlocked(creatorId, confirm === "block", reason),
              () => {
                close();
                if (confirm === "delete") router.push("/admin/creators");
              },
            )
          }
        />
      ) : null}
    </div>
  );
}
