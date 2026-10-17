import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { ReviewActions } from "@/components/onboarding/review-actions";
import { StatusBadge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { formatCompact, formatRelative } from "@/lib/format";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("onboarding.queue.title") };
}

/** Creators who finished onboarding and wait for approval, oldest first. */
export default async function ApprovalsPage() {
  const { supabase, me } = await requireStaff("creator.read");
  const t = await getTranslations();
  const { data, error } = await supabase.rpc("approvals_queue");
  const canReview = me.permissions.has("creator.write");
  return (
    <>
      <Link href="/admin/creators" className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink">
        <ArrowLeft className="size-4" aria-hidden /> {t("nav.admin.creators")}
      </Link>
      <PageHeader title={t("onboarding.queue.title")} description={t("onboarding.queue.subtitle")} />
      <Card>
        {error ? <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} /> : null}
        {!error && data.length === 0 ? (
          <EmptyState title={t("onboarding.queue.empty")} description={t("onboarding.queue.emptyHint")} />
        ) : null}
        <ul className="flex flex-col divide-y divide-line">
          {(data ?? []).map((r) => (
            <li key={r.creator_id} className="flex flex-col gap-3 py-3 md:flex-row md:items-center">
              <div className="min-w-0 flex-1">
                <Link href={`/admin/creators/${r.creator_id}`} className="font-medium text-primary hover:underline">
                  {r.display_name}
                </Link>
                <p className="text-xs text-muted">
                  @{r.handle} · {t("onboarding.queue.followers", { count: formatCompact(r.followers) })} ·{" "}
                  {t(`onboarding.queue.source.${r.source === "self_signup" ? "self" : "invited"}`)} ·{" "}
                  {formatRelative(r.submitted_at)}
                  {r.owner_name ? ` · ${r.owner_name}` : ""}
                </p>
              </div>
              <StatusBadge status={r.kyc_status} label={t(`kyc.status.${r.kyc_status as "pending"}`)} />
              {canReview ? <ReviewActions creatorId={r.creator_id} name={r.display_name} /> : null}
            </li>
          ))}
        </ul>
      </Card>
    </>
  );
}
