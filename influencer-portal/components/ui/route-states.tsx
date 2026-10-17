"use client";
import { useTranslations } from "next-intl";
import { useEffect } from "react";
import { Button } from "./button";
import { ErrorState, ListSkeleton, Skeleton } from "./states";

export function PageLoading() {
  const t = useTranslations();
  return (
    <div className="flex flex-col gap-4">
      <Skeleton className="h-8 w-56" />
      <Skeleton className="h-4 w-80 max-w-full" />
      <ListSkeleton rows={5} label={t("common.loading")} />
    </div>
  );
}

/** Route error boundary: never shows the raw error (it could carry data); offers a retry. */
export function PageError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  const t = useTranslations();
  useEffect(() => {
    console.error("[route-error]", error.digest ?? "");
  }, [error]);
  return (
    <ErrorState
      title={t("errors.pageFailed")}
      description={error.digest ? t("errors.reference", { ref: error.digest }) : t("errors.tryAgain")}
      action={
        <Button variant="secondary" onClick={reset}>
          {t("common.retry")}
        </Button>
      }
    />
  );
}
