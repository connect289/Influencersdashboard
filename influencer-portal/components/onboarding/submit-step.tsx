"use client";
import { CheckCircle2, Circle } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { Banner } from "@/components/ui/states";
import { useAction } from "@/components/ui/use-action";
import { submitOnboarding } from "@/lib/actions/onboarding";
import { ONBOARDING_STEPS, type OnboardingStep } from "@/lib/creators/onboarding";

export function SubmitStep({
  steps,
  submitted,
  complete,
}: {
  steps: Record<OnboardingStep, boolean>;
  submitted: boolean;
  complete: boolean;
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  return (
    <Card>
      <CardHeader title={t("onboarding.submit.title")} description={t("onboarding.submit.hint")} />
      {submitted ? <Banner>{t("onboarding.submit.waiting")}</Banner> : null}
      <ul className="my-3 flex flex-col gap-2">
        {ONBOARDING_STEPS.map((s) => (
          <li key={s} className="flex items-center gap-2 text-sm">
            {steps[s] ? (
              <CheckCircle2 className="size-5 text-success" aria-label={t("overview.done")} />
            ) : (
              <Circle className="size-5 text-muted" aria-label={t("overview.todo")} />
            )}
            {steps[s] ? (
              t(`onboarding.steps.${s}`)
            ) : (
              <Link href={`/creator/onboarding?step=${s}`} className="text-primary underline-offset-4 hover:underline">
                {t(`onboarding.steps.${s}`)}
              </Link>
            )}
          </li>
        ))}
      </ul>
      {!submitted ? (
        <Button
          disabled={pending || !complete}
          onClick={() =>
            run(
              () => submitOnboarding(),
              () => router.refresh(),
            )
          }
        >
          {t("onboarding.submit.button")}
        </Button>
      ) : null}
    </Card>
  );
}
