import { getTranslations } from "next-intl/server";
import { GrantsEditor } from "@/components/agency/grants-editor";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { requireCreator } from "@/lib/auth/guards";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.creator.agency") };
}

/** Agencies that manage (or want to manage) this creator, and what each may do. */
export default async function CreatorAgencyPage() {
  const { supabase } = await requireCreator();
  const t = await getTranslations();
  const { data, error } = await supabase.rpc("my_agency_links");
  const links = data ?? [];
  return (
    <>
      <PageHeader title={t("agencies.creatorTitle")} description={t("agencies.creatorSubtitle")} />
      {error ? (
        <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
      ) : null}
      {!error && links.length === 0 ? (
        <EmptyState
          title={t("agencies.creatorEmpty")}
          description={t("agencies.creatorEmptyHint")}
        />
      ) : null}
      <div className="flex flex-col gap-4">
        {links.map((l) => (
          <GrantsEditor key={l.link_id} link={l} />
        ))}
      </div>
    </>
  );
}
