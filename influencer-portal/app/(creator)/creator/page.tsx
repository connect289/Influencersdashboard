import Link from "next/link";
import { ChevronRight, FileCheck2 } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { requireCreator } from "@/lib/auth/guards";
import { onboardingState, progressPct } from "@/lib/creators/onboarding";

interface Action {
  key: string;
  title: string;
  hint: string;
  href: string;
}

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.creator.home") };
}

/** Creator home. The action centre lists only things that exist and need the creator; later phases add their items. */
export default async function CreatorHome() {
  const { supabase, me } = await requireCreator();
  const t = await getTranslations();
  const [terms, onboarding] = await Promise.all([supabase.rpc("terms_pending"), supabase.rpc("onboarding_state")]);
  const state = onboardingState.safeParse(onboarding.data);
  const actions: Action[] = [];
  if (state.success && !state.data.approved)
    actions.push(
      state.data.submitted_at
        ? {
            key: "onboarding",
            title: t("home.actions.onboardingReview"),
            hint: t("home.actions.onboardingReviewHint"),
            href: "/creator/onboarding?step=submit",
          }
        : {
            key: "onboarding",
            title: t("home.actions.onboarding"),
            hint: t("home.actions.onboardingHint", { pct: progressPct(state.data) }),
            href: "/creator/onboarding",
          },
    );
  if ((terms.data ?? []).length > 0 && !(state.success && !state.data.approved))
    actions.push({
      key: "terms",
      title: t("home.actions.terms"),
      hint: t("home.actions.termsHint"),
      href: "/creator/terms",
    });
  return (
    <>
      <PageHeader
        title={t("home.title", { name: me.displayName.split(" ")[0] ?? me.displayName })}
        description={t("home.subtitle")}
      />
      <Card>
        <CardHeader
          title={t("home.actionCentre")}
          description={actions.length ? t("home.actionsCount", { count: actions.length }) : undefined}
        />
        {terms.error ? <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} /> : null}
        {!terms.error && actions.length === 0 ? (
          <EmptyState title={t("home.noActions")} description={t("home.noActionsHint")} />
        ) : null}
        <ul className="flex flex-col gap-2">
          {actions.map((a) => (
            <li key={a.key}>
              <Link
                href={a.href}
                className="flex items-center gap-3 rounded-xl bg-accent-soft px-3 py-3 text-accent-ink hover:opacity-90"
              >
                <FileCheck2 className="size-5 shrink-0" aria-hidden />
                <span className="min-w-0 flex-1">
                  <span className="block text-sm font-medium">{a.title}</span>
                  <span className="block text-xs">{a.hint}</span>
                </span>
                <ChevronRight className="size-4" aria-hidden />
              </Link>
            </li>
          ))}
        </ul>
      </Card>
    </>
  );
}
