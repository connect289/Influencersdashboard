"use client";
import { useTranslations } from "next-intl";
import { useTransition } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { retryJob } from "@/lib/actions/system";

export function RetryButton({ id }: { id: number }) {
  const t = useTranslations();
  const [pending, start] = useTransition();
  return (
    <Button
      variant="secondary"
      size="sm"
      disabled={pending}
      onClick={() =>
        start(async () => {
          const r = await retryJob(id);
          if (r.ok) toast.success(r.message ?? "");
          else toast.error(r.error);
        })
      }
    >
      {t("system.retry")}
    </Button>
  );
}
