"use client";
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { useAction } from "@/components/ui/use-action";
import { createBriefForDeal } from "@/lib/actions/content";

/** Creates the deal's draft brief and deliverables from its campaign's template, then opens the brief. */
export function CreateBriefButton({ dealId }: { dealId: string }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  return (
    <Button
      size="sm"
      disabled={pending}
      onClick={() =>
        run(
          () => createBriefForDeal(dealId),
          (d) => d && router.push(`/admin/briefs/${d.id}`),
        )
      }
    >
      {t("content.deal.createBrief")}
    </Button>
  );
}
