// Display labels for breakdown keys: names come from the database for creators, campaigns and programmes;
// platforms, content types and deal models are translated; rows without a key are facts that are not split.
import type { Dimension } from "./data";

type T = (key: string) => string;

export function dimensionLabel(dim: Dimension, key: string | null, label: string | null, t: T): string {
  if (key === null) return t("analytics.notSplit");
  switch (dim) {
    case "platform":
      return t(`platforms.${key}`);
    case "content_type":
      return t(`formats.${key}`);
    case "deal_model":
      return t(`deals.models.${key}`);
    default:
      return label ?? key;
  }
}

export function dimensionHref(dim: Dimension, key: string | null, search: string): string | undefined {
  if (key === null) return undefined;
  const q = search ? `?${search}` : "";
  if (dim === "creator") return `/admin/creators/${key}?tab=analytics${search ? `&${search}` : ""}`;
  if (dim === "campaign") return `/admin/analytics/campaigns/${key}${q}`;
  return undefined;
}
