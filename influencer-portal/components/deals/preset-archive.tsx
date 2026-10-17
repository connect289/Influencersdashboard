"use client";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { Button } from "@/components/ui/button";
import { useAction } from "@/components/ui/use-action";
import { archivePreset } from "@/lib/actions/deals";

export function PresetArchiveButton({ id, archived }: { id: string; archived: boolean }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  return (
    <Button
      variant="ghost"
      size="sm"
      disabled={pending}
      onClick={() =>
        run(
          () => archivePreset(id, !archived),
          () => router.refresh(),
        )
      }
    >
      {archived ? t("deals.presets.restore") : t("deals.presets.archive")}
    </Button>
  );
}
