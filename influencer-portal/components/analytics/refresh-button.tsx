"use client";
import { RefreshCw } from "lucide-react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { Button } from "@/components/ui/button";
import { useAction } from "@/components/ui/use-action";
import { refreshAnalytics } from "@/lib/actions/analytics";

export function RefreshButton() {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  return (
    <Button
      size="sm"
      variant="ghost"
      disabled={pending}
      onClick={() =>
        run(
          () => refreshAnalytics(),
          () => router.refresh(),
        )
      }
    >
      <RefreshCw className={pending ? "animate-spin" : undefined} /> {t("analytics.refresh")}
    </Button>
  );
}
