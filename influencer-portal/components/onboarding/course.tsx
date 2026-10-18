"use client";
import { CheckCircle2, XCircle } from "lucide-react";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { Banner } from "@/components/ui/states";
import { useAction } from "@/components/ui/use-action";
import { submitCourse, type CourseResult } from "@/lib/actions/onboarding";
import { cn } from "@/lib/utils";

export interface CourseContent {
  lessons: { id: string; title: string; body: string }[];
  questions: { id: string; prompt: string; options: string[] }[];
  pass_pct: number;
}

/** The compliance mini-course: read the lessons, then answer the quiz. Graded in the database. */
export function Course({ content, passed }: { content: CourseContent; passed: boolean }) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const [answers, setAnswers] = useState<Record<string, number>>({});
  const [result, setResult] = useState<CourseResult | null>(null);
  const wrong = new Map((result?.wrong ?? []).map((w) => [w.id, w.explanation]));
  const answered = Object.keys(answers).length;
  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardHeader title={t("onboarding.course.lessonsTitle")} description={t("onboarding.course.lessonsHint")} />
        <ol className="flex flex-col gap-4">
          {content.lessons.map((l, i) => (
            <li key={l.id}>
              <h3 className="text-sm font-semibold">
                {i + 1}. {l.title}
              </h3>
              <p className="mt-1 text-sm leading-relaxed text-muted">{l.body}</p>
            </li>
          ))}
        </ol>
      </Card>
      <Card>
        <CardHeader
          title={t("onboarding.course.quizTitle")}
          description={t("onboarding.course.quizHint", { pct: content.pass_pct })}
        />
        {passed && !result ? <Banner tone="success">{t("onboarding.course.alreadyPassed")}</Banner> : null}
        {result ? (
          <Banner tone={result.passed ? "success" : "warning"}>
            {result.passed
              ? t("onboarding.course.passed", { score: result.score_pct ?? 0 })
              : t("onboarding.course.failed", {
                  score: result.score_pct ?? 0,
                  pct: result.pass_pct ?? content.pass_pct,
                })}
          </Banner>
        ) : null}
        <form
          className="mt-3 flex flex-col gap-5"
          onSubmit={(e) => {
            e.preventDefault();
            run(
              () => submitCourse(answers),
              (r) => r && setResult(r),
            );
          }}
        >
          {content.questions.map((q, i) => {
            const isWrong = result && wrong.has(q.id);
            const isRight = result && !wrong.has(q.id);
            return (
              <fieldset key={q.id} className="flex flex-col gap-2">
                <legend className="mb-1 flex items-start gap-2 text-sm font-medium">
                  {isRight ? (
                    <CheckCircle2
                      className="mt-0.5 size-4 shrink-0 text-success"
                      aria-label={t("onboarding.course.right")}
                    />
                  ) : null}
                  {isWrong ? (
                    <XCircle className="mt-0.5 size-4 shrink-0 text-danger" aria-label={t("onboarding.course.wrong")} />
                  ) : null}
                  <span>
                    {i + 1}. {q.prompt}
                  </span>
                </legend>
                {q.options.map((o, idx) => (
                  <label
                    key={o}
                    className={cn(
                      "flex items-start gap-2 rounded-xl px-3 py-2 text-sm ring-1 ring-line ring-inset",
                      answers[q.id] === idx && "bg-primary-soft ring-primary",
                    )}
                  >
                    <input
                      type="radio"
                      name={q.id}
                      className="mt-0.5 size-4 accent-[var(--primary)]"
                      checked={answers[q.id] === idx}
                      onChange={() => setAnswers((a) => ({ ...a, [q.id]: idx }))}
                    />
                    {o}
                  </label>
                ))}
                {isWrong && wrong.get(q.id) ? <p className="text-xs text-danger">{wrong.get(q.id)}</p> : null}
              </fieldset>
            );
          })}
          <Button type="submit" disabled={pending || answered < content.questions.length}>
            {result && !result.passed ? t("onboarding.course.retry") : t("onboarding.course.submit")}
          </Button>
          {answered < content.questions.length ? (
            <p className="text-xs text-muted">
              {t("onboarding.course.answered", { answered, total: content.questions.length })}
            </p>
          ) : null}
        </form>
      </Card>
    </div>
  );
}
