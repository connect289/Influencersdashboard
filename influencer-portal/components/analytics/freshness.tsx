// When the staff dashboards' summary views were last refreshed, with a refresh button.
import { useTranslations } from "next-intl";
import { formatRelative } from "@/lib/format";
import { RefreshButton } from "./refresh-button";

export function Freshness({ refreshedAt }: { refreshedAt: string | null }) {
  const t = useTranslations();
  return (
    <p className="flex items-center gap-1 text-xs text-muted">
      {refreshedAt ? t("analytics.updated", { when: formatRelative(refreshedAt) }) : t("analytics.notRefreshed")}
      <RefreshButton />
    </p>
  );
}
