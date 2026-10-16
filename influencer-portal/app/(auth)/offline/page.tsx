import { getTranslations } from "next-intl/server";

export default async function Offline() {
  const t = await getTranslations();
  return (
    <div className="flex flex-col gap-2 text-center">
      <h1 className="text-xl font-semibold">{t("offline.title")}</h1>
      <p className="text-sm text-muted">{t("offline.body")}</p>
    </div>
  );
}
