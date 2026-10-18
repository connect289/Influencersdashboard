import Link from "next/link";
import { CheckCircle2 } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { AcceptTerms } from "@/components/creator/accept-terms";
import { KycForm } from "@/components/creator-profile/kyc-form";
import { PlatformsCard } from "@/components/creator-profile/platforms-card";
import { ProfileForm } from "@/components/creator-profile/profile-form";
import { Course, type CourseContent } from "@/components/onboarding/course";
import { SubmitStep } from "@/components/onboarding/submit-step";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { Banner, EmptyState, ErrorState } from "@/components/ui/states";
import { requireCreator } from "@/lib/auth/guards";
import { loadCreatorProfile, loadKyc } from "@/lib/creators/load";
import { currentStep, onboardingState, progressPct, WIZARD_STEPS, type WizardStep } from "@/lib/creators/onboarding";
import { formatDate } from "@/lib/format";
import { cn } from "@/lib/utils";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("onboarding.title") };
}

/** The onboarding wizard (spec 13): profile, platforms, KYC, terms, compliance course, then submit for approval. */
export default async function OnboardingPage({ searchParams }: { searchParams: Promise<{ step?: string }> }) {
  const { supabase, me } = await requireCreator();
  const t = await getTranslations();
  const raw = await supabase.rpc("onboarding_state");
  const parsed = raw.error ? null : onboardingState.safeParse(raw.data);
  if (!parsed?.success) return <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />;
  const state = parsed.data;

  if (state.approved)
    return (
      <>
        <PageHeader title={t("onboarding.title")} />
        <EmptyState
          icon={<CheckCircle2 />}
          title={t("onboarding.approvedTitle")}
          description={t("onboarding.approvedHint")}
          action={
            <Button asChild>
              <Link href="/creator">{t("nav.creator.home")}</Link>
            </Button>
          }
        />
      </>
    );

  const step = currentStep(state, (await searchParams).step);
  const done = (s: WizardStep) => (s === "submit" ? Boolean(state.submitted_at) : state.steps[s]);
  const idx = WIZARD_STEPS.indexOf(step);
  const next = WIZARD_STEPS[idx + 1];

  let body: React.ReactNode;
  if (step === "profile" || step === "platforms") {
    const { data } = await loadCreatorProfile(supabase, me.creatorId);
    body = !data ? (
      <ErrorState title={t("errors.loadFailed")} />
    ) : step === "profile" ? (
      <>
        <Banner>{t("onboarding.profileHint")}</Banner>
        <ProfileForm creator={data.creator} canEdit />
      </>
    ) : (
      <PlatformsCard creatorId={me.creatorId} platforms={data.platforms} canEdit />
    );
  } else if (step === "kyc") {
    const kyc = await loadKyc(supabase, me.creatorId);
    body = kyc ? (
      <>
        {!state.kyc_required ? <Banner>{t("onboarding.kycOptional")}</Banner> : null}
        <KycForm creatorId={me.creatorId} kyc={kyc} canEdit />
      </>
    ) : (
      <ErrorState title={t("errors.loadFailed")} />
    );
  } else if (step === "terms") {
    const { data, error } = await supabase.rpc("terms_pending");
    body = error ? (
      <ErrorState title={t("errors.loadFailed")} />
    ) : data.length === 0 ? (
      <EmptyState
        title={t("terms.allAccepted")}
        description={state.steps.terms ? undefined : t("onboarding.termsMissing")}
      />
    ) : (
      <div className="flex flex-col gap-4">
        {data.map((p) => (
          <Card key={p.id}>
            <CardHeader
              title={p.title}
              description={t("terms.version", {
                version: p.version,
                date: formatDate(p.effective_at),
              })}
            />
            <div className="mb-4 max-h-80 overflow-y-auto rounded-xl bg-surface-2 p-4 text-sm whitespace-pre-line">
              {p.body}
            </div>
            <AcceptTerms id={p.id} />
          </Card>
        ))}
      </div>
    );
  } else if (step === "course") {
    const { data, error } = await supabase.rpc("course_content");
    body =
      error || !data ? (
        <ErrorState title={t("errors.loadFailed")} />
      ) : (
        <Course content={data as unknown as CourseContent} passed={state.steps.course} />
      );
  } else {
    body = <SubmitStep steps={state.steps} submitted={Boolean(state.submitted_at)} complete={state.complete} />;
  }

  return (
    <>
      <PageHeader
        title={t("onboarding.title")}
        description={t("onboarding.subtitle", { pct: progressPct(state) })}
        help="/creator/help/creator#onboarding"
      />
      <div
        className="mb-4 h-2 overflow-hidden rounded-full bg-surface-2"
        role="progressbar"
        aria-valuenow={progressPct(state)}
        aria-valuemin={0}
        aria-valuemax={100}
        aria-label={t("onboarding.progress")}
      >
        <div className="h-full bg-primary transition-all" style={{ width: `${String(progressPct(state))}%` }} />
      </div>
      <nav aria-label={t("onboarding.stepsLabel")} className="-mx-4 mb-4 overflow-x-auto px-4 md:mx-0 md:px-0">
        <ol className="flex gap-1.5">
          {WIZARD_STEPS.map((s, i) => (
            <li key={s}>
              <Link
                href={`/creator/onboarding?step=${s}`}
                aria-current={s === step ? "step" : undefined}
                className={cn(
                  "flex items-center gap-1.5 rounded-full px-3 py-1.5 text-sm whitespace-nowrap ring-1 ring-line ring-inset",
                  s === step && "bg-primary text-on-primary ring-primary",
                  s !== step && done(s) && "text-success",
                )}
              >
                {done(s) ? (
                  <CheckCircle2 className="size-4" aria-hidden />
                ) : (
                  <span className="text-xs tabular-nums">{i + 1}</span>
                )}
                {t(`onboarding.steps.${s}`)}
                {done(s) ? <span className="sr-only">{t("overview.done")}</span> : null}
              </Link>
            </li>
          ))}
        </ol>
      </nav>
      <div className="flex flex-col gap-4">
        {body}
        {next && step !== "submit" ? (
          <div className="flex justify-end">
            <Button asChild variant={done(step) ? "primary" : "secondary"}>
              <Link href={`/creator/onboarding?step=${next}`}>
                {done(step) ? t("onboarding.next") : t("onboarding.skipForNow")}
              </Link>
            </Button>
          </div>
        ) : null}
      </div>
    </>
  );
}
