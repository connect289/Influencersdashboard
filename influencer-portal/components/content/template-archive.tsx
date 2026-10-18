"use client";
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { useAction } from "@/components/ui/use-action";
import { archiveBriefTemplate } from "@/lib/actions/content";

export function TemplateArchiveButton({ id, archived }: { id: string; archived: boolean }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  if (archived)
    return (
      <Button
        size="sm"
        variant="secondary"
        disabled={pending}
        onClick={() =>
          run(
            () => archiveBriefTemplate(id, false),
            () => router.refresh(),
          )
        }
      >
        {t("content.templates.restore")}
      </Button>
    );
  return (
    <ConfirmDialog
      trigger={
        <Button size="sm" variant="ghost">
          {t("content.templates.archive")}
        </Button>
      }
      title={t("content.templates.archiveTitle")}
      description={t("content.templates.archiveHint")}
      actionLabel={t("content.templates.archive")}
      pending={pending}
      onConfirm={(_, close) =>
        run(
          () => archiveBriefTemplate(id, true),
          () => {
            close();
            router.refresh();
          },
        )
      }
    />
  );
}
