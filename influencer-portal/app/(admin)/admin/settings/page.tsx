import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { SettingCard, type SettingRow } from "@/components/settings/setting-card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { SETTING_GROUPS, type SettingGroup } from "@/lib/settings/registry";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.settings") };
}

export default async function SettingsPage() {
  const { supabase, me } = await requireStaff();
  if (!["settings.read", "settings.write", "tax.manage", "tier.manage"].some((p) => me.permissions.has(p as never)))
    notFound();
  const t = await getTranslations();
  const { data, error } = await supabase.rpc("settings_list");
  const rows = (data ?? []) as (SettingRow & { grp: string })[];
  const groups = (Object.keys(SETTING_GROUPS) as SettingGroup[])
    .map((g) => ({ g, rows: rows.filter((r) => r.grp === g) }))
    .filter((x) => x.rows.length);
  return (
    <>
      <PageHeader title={t("nav.admin.settings")} description={t("settings.subtitle")} />
      {error ? <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} /> : null}
      {!error && rows.length === 0 ? <EmptyState title={t("settings.empty")} /> : null}
      <div className="flex flex-col gap-8">
        {groups.map(({ g, rows: rs }) => (
          <section key={g} aria-labelledby={`group-${g}`} className="flex flex-col gap-4">
            <h2 id={`group-${g}`} className="text-sm font-semibold tracking-wide text-muted uppercase">
              {t(`settingGroups.${g}`)}
            </h2>
            {rs.map((r) => (
              <SettingCard key={r.key} row={r} />
            ))}
          </section>
        ))}
      </div>
    </>
  );
}
