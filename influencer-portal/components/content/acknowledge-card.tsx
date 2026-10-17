"use client";
import { CheckCircle2 } from "lucide-react";
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { useAction } from "@/components/ui/use-action";
import { acknowledgeBrief } from "@/lib/actions/content";

/** The creator confirms they have read the current version of the brief; work starts from here. */
export function AcknowledgeCard({
  briefId,
  versionId,
  acknowledged,
}: {
  briefId: string;
  versionId: string;
  acknowledged: boolean;
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [read, setRead] = useState(false);
  if (acknowledged)
    return (
      <p className="mb-4 flex items-center gap-2 rounded-xl bg-success-soft px-3 py-2 text-sm text-success">
        <CheckCircle2 className="size-4" aria-hidden /> {t("content.brief.youAcknowledged")}
      </p>
    );
  return (
    <Card className="mb-4 flex flex-col gap-3 ring-2 ring-primary/30">
      <p className="text-sm font-medium">{t("content.brief.ackTitle")}</p>
      <label className="flex items-start gap-2 text-sm">
        <input type="checkbox" className="mt-1 size-4" checked={read} onChange={(e) => setRead(e.target.checked)} />
        <span>{t("content.brief.ackLabel")}</span>
      </label>
      <Button
        type="button"
        className="self-start"
        disabled={!read || pending}
        onClick={() =>
          run(
            () => acknowledgeBrief(briefId, versionId),
            () => router.refresh(),
          )
        }
      >
        {t("content.brief.acknowledge")}
      </Button>
    </Card>
  );
}
