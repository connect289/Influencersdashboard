import "server-only";
import { getTranslations } from "next-intl/server";
import type { PdfLabels } from "./pdf";

export async function pdfLabels(): Promise<PdfLabels> {
  const t = await getTranslations();
  return {
    brand: t("app.name"),
    about: t("mediaKit.about"),
    reach: t("mediaKit.reach"),
    platformsCount: t("mediaKit.platformsCount"),
    engagement: t("mediaKit.engagement"),
    platforms: t("profile.platforms.title"),
    platform: t("profile.platforms.platform"),
    followers: t("profile.platforms.followers"),
    avgViews: t("profile.platforms.avgViews"),
    er: t("profile.platforms.engagement"),
    rates: t("profile.rates.title"),
    format: t("profile.rates.format"),
    price: t("mediaKit.price"),
    topics: t("profile.fields.niches"),
    languages: t("profile.fields.languages"),
    work: t("profile.portfolio.title"),
    footer: t("mediaKit.footer"),
    platformName: (p) => t(`platforms.${p}`),
    formatName: (f) => t(`formats.${f}`),
  };
}
