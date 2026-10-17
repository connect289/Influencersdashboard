import Link from "next/link";
import { ChevronRight } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { GrantBadges } from "@/components/agency/grant-badges";
import { LinkRequest } from "@/components/agency/link-request";
import { StatusBadge } from "@/components/ui/badge";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { requireAgency } from "@/lib/auth/guards";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.agency.home") };
}

/** The agency's creators: active links (with what each creator granted) and requests waiting for the creator. */
export default async function AgencyHome() {
  const { supabase, me } = await requireAgency();
  const t = await getTranslations();
  const { data, error } = await supabase.rpc("agency_creators");
  const rows = data ?? [];
  return (
    <>
      <PageHeader
        title={t("agencyPortal.title")}
        description={t("agencyPortal.subtitle", { agency: me.agencyName })}
        help="/agency/help/agency#linking"
      />
      <div className="flex flex-col gap-4">
        <Card>
          <CardHeader title={t("agencyPortal.creators")} />
          {error ? <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} /> : null}
          {!error && rows.length === 0 ? (
            <EmptyState
              title={t("agencyPortal.empty")}
              description={me.isOwner ? t("agencyPortal.emptyOwner") : t("agencyPortal.emptyMember")}
            />
          ) : null}
          <ul className="flex flex-col divide-y divide-line">
            {rows.map((r) => {
              const body = (
                <>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-sm font-medium">{r.display_name}</span>
                    <span className="block text-xs text-muted">@{r.handle}</span>
                    {r.link_status === "active" ? (
                      <span className="mt-1 block">
                        <GrantBadges grants={r} />
                      </span>
                    ) : null}
                  </span>
                  {r.link_status === "pending" ? (
                    <StatusBadge status="pending" label={t("agencies.links.status.pending")} />
                  ) : (
                    <ChevronRight className="size-4 text-muted" aria-hidden />
                  )}
                </>
              );
              return (
                <li key={r.link_id}>
                  {r.link_status === "active" ? (
                    <Link
                      href={`/agency/creators/${r.creator_id}`}
                      className="flex items-center gap-3 py-3 hover:opacity-90"
                    >
                      {body}
                    </Link>
                  ) : (
                    <div className="flex items-center gap-3 py-3">{body}</div>
                  )}
                </li>
              );
            })}
          </ul>
        </Card>
        {me.isOwner ? (
          <Card>
            <CardHeader title={t("agencies.links.requestTitle")} description={t("agencies.links.requestHint")} />
            <LinkRequest agencyId={me.agencyId} />
          </Card>
        ) : null}
      </div>
    </>
  );
}
